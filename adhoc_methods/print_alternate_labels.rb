def create_order_to_clickpost(dispatch_plan_ids)
  counter = 1
  dp_data = []
  DispatchPlan.where(id: dispatch_plan_ids).each do |dispatch_plan|
    shipment = dispatch_plan.shipment
    #next if shipment.packaging_labels.present?
    shipment.packaging_labels.delete_all if shipment.packaging_labels.present?

    p "#{counter}. Running for DP: #{dispatch_plan.id}"

    if shipment.no_of_packages != 1
      shipment.update(no_of_packages: 1) if is_dpirs_belong_to_ppe_category(dispatch_plan)
    end
    begin
      @response = Hashie::Mash.new(LogisticsDispatcher::Communicator.create_order(create_order_creation_params(shipment.id)))
      response = @response.meta

      if @response.error.present?
        p "    ERROR: Couldn't run for shipment #{shipment.id} due to #{response.message}"
        dp_data.push(dispatch_plan.id)
      elsif response.status.present? && response.status == 200 || response.status == 323
        p "    SUCCESS: Ran, and updated shipment #{shipment.id}"
        p "         Tracking ID: #{@response.result.waybill}"
        p "         Label: #{@response.result.label}"

        update_shipment(@response, shipment.id)
      else
        p "    Something went wrong.."
        dp_data.push(dispatch_plan.id)
      end
    rescue => e
      p "SOMETHING WENT WRONG: #{e}"
    end

    counter = counter + 1
  end
  dp_data
end

def update_shipment(response, shipment_id)
  errors = []
  shipment = Shipment.find_by_id(shipment_id)

  ActiveRecord::Base.transaction do

    if shipment.present?
      shipment.tracking_id = response.result.waybill
      shipment.clickpost_tracking_id = response.result.waybill
      shipment.clickpost_order_creation_errors = ""

      unless shipment.save
        Rails.logger.error "Shipment tracking number and packaging label not updated because of #{shipment.errors.full_messages.join(', ')}"

        errors << shipment.errors.full_messages
      end

      packaging_label = PackagingLabel.new
      packaging_label.file = URI.open(response.result.label)
      packaging_label.shipment_id = shipment_id

      unless packaging_label.save
        Rails.logger.error "Packaging label not created for shipment id #{shipment_id} because #{packaging_label.errors.full_messages.join(', ')}"

        errors << packaging_label.errors.full_messages
      end
    end

    raise ActiveRecord::Rollback if errors.present?
  end

  shipment.generate_combined_invoice_label_file
end

def is_dpirs_belong_to_ppe_category(dispatch_plan)
  dpirs = dispatch_plan.dispatch_plan_item_relations

  dpirs.each do |dpir|
    if dpir.product_details["category_hierarchy"].present? && dpir.product_details["sub_sub_category_id"].present?
      category_name = dpir.product_details["category_hierarchy"].first
      sub_sub_category_id = dpir.product_details["sub_sub_category_id"]
    else
      product = Hashie::Mash.new(CataloguingService::Communicator.fetch_product(dpir.master_sku_id))
      sub_sub_category_id = product.category_id
      category = Hashie::Mash.new(CataloguingService::Communicator.fetch_category(sub_sub_category_id))
      category_name = category.category.hierarchy.first if category.category.present?
    end
    if category_name.present? && sub_sub_category_id.present? &&
      (APP_CONFIG["ppe_categories"].include?(category_name) || APP_CONFIG["ppe_ssc_ids"].include?(sub_sub_category_id) || APP_CONFIG["ppe_master_sku_ids"].include?(dpir.master_sku_id))
      return true
    end
  end

  return false
end

def create_order_creation_params(shipment_id)
  @shipment = Shipment.find(shipment_id)
  if @shipment.invoice.present? && @shipment.invoice.dc?
    @invoice_no = @shipment.buyer_delivery_challan_no.present? ? @shipment.buyer_delivery_challan_no : @shipment.return_delivery_challan_no
  else
    @invoice_no = @shipment.buyer_invoice_no
  end
  ptl_or_ftl = @shipment.dispatch_plan.ptl_or_ftl
  if ptl_or_ftl == "PTL"
    vehicle_type = @shipment.suggested_truck_size || @shipment.truck_size
  else
    vehicle_type = @shipment.dispatch_plan.truck_type
  end

  if @shipment.dispatch_plan.origin_address.present? && @shipment.dispatch_plan.origin_address.warehouse.present?
    warehouse_name = @shipment.dispatch_plan.origin_address.warehouse.warehouse_name
  end

  @request_params = {
    shipment_details: {
      cod_value: 00,
      invoice_date: @shipment.created_at.strftime("%Y-%m-%d"),
      order_type: "PREPAID",
      invoice_number: @invoice_no,
      invoice_value: @shipment.total_buyer_invoice_amount.to_f.round(2),
      shipment_type: "MPS",
      breadth: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      length: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      height: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      weight: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      items: get_item_details
    },
    pickup_info: get_pick_up_info,
    drop_info: get_drop_info,
    courier_partner: @shipment.transporter.clickpost_cp_id,
    reference_number: @shipment.id.to_s + "-BZ",
    weight: 1.1,
    additional: {
      label: true,
      data_validation: true,
      delivery_type: "FORWARD",
      account_code: @shipment.transporter.clickpost_account_code,
      region: @shipment.dispatch_plan.region,
      warehouse_name: warehouse_name,
      vehicle_type: vehicle_type,
      return_info: {
        email: @seller_email || "support@clickpost.in",
        name: only_alphabets(@shipment.dispatch_plan.origin_address.company_name),
        phone: @shipment.dispatch_plan.origin_address.mobile_number,
        address: @shipment.dispatch_plan.origin_address.street_address,
        country: @shipment.dispatch_plan.origin_address.country,
        city: @shipment.dispatch_plan.origin_address.city,
        pincode: @shipment.dispatch_plan.origin_address.pincode,
        state: @shipment.dispatch_plan.origin_address.state
      }
    }
  }
  result = Hashie::Mash.new(@request_params)
  result
end

def pretty_json(result)
  puts JSON.pretty_generate(result).gsub("=>", ": ").gsub("nil", "null")
end

def get_pick_up_info
  pickup_info = {
    pickup_time: @shipment.created_at.iso8601,
    email: @seller_email || "support@clickpost.in",
    pickup_address: @shipment.dispatch_plan.origin_address.street_address,
    pickup_state: @shipment.dispatch_plan.origin_address.state,
    pickup_name: only_alphabets(@shipment.dispatch_plan.origin_address.company_name),
    pickup_country: @shipment.dispatch_plan.origin_address.country,
    tin: @shipment.dispatch_plan.origin_address.gstin,
    pickup_city: @shipment.dispatch_plan.origin_address.city,
    pickup_phone: @shipment.dispatch_plan.origin_address.mobile_number,
    pickup_pincode: @shipment.dispatch_plan.origin_address.pincode
  }

  return pickup_info
end

def get_drop_info
  drop_info = {
    drop_country: @shipment.dispatch_plan.destination_address.country,
    drop_city: @shipment.dispatch_plan.destination_address.city,
    drop_phone: @shipment.dispatch_plan.destination_address.mobile_number,
    drop_address: @shipment.dispatch_plan.destination_address.street_address,
    drop_name: only_alphabets(@shipment.dispatch_plan.destination_address.company_name),
    drop_state: @shipment.dispatch_plan.destination_address.state,
    drop_pincode: @shipment.dispatch_plan.destination_address.pincode,
    drop_email: @buyer_email || "support@clickpost.in"
  }

  return drop_info
end

def get_item_details

  no_of_packages = @shipment.no_of_packages

  if no_of_packages >= 1.0
    items_array = items_array_by_no_of_packages(no_of_packages)
  else
    items_array = items_array_by_dispatch_plan_item_relations
  end

  return items_array
end

def get_order_item_details(order_item_id)
  order_item_response = Bizongo::Communicator.order_items_index!({ ids: [order_item_id], invoice_response: true })
  order_item = order_item_response[:order_items].first

  @seller_email = order_item_response[:seller_company][:primary_contact][:email] if order_item_response[:seller_company].present? && order_item_response[:seller_company][:primary_contact].present? && order_item_response[:seller_company][:primary_contact][:email].present?

  @buyer_email = order_item_response[:direct_order][:buyer][:email] if order_item_response[:direct_order].present? && order_item_response[:direct_order][:buyer].present? && order_item_response[:direct_order][:buyer][:email].present?

  order_item_hash = {
    hsn_number: order_item[:hsn_number],
    master_sku_code: order_item[:master_sku_code]
  }

  return order_item_hash
end

def get_child_product_details(child_product_id)
  child_product_response = Bizongo::Communicator.child_products_index!({ ids: [child_product_id] })
  child_product = child_product_response[:child_products].first

  child_product_hash = {
    hsn_number: child_product[:hsn_number],
    master_sku_code: child_product[:sku_code]
  }

  return child_product_hash
end

def items_array_by_no_of_packages(no_of_packages)
  hsn_numbers = []
  master_sku_codes = []
  price = 0.0
  price_per_unit = 0.0
  quantity = 0.0
  product_names = []

  @shipment.dispatch_plan_item_relations.each do |dpir|
    if dpir.order_item_id.present?
      order_item_details = get_order_item_details(dpir.order_item_id)

      hsn_numbers << order_item_details[:hsn_number] if order_item_details[:hsn_number].present?
      master_sku_codes << order_item_details[:master_sku_code] if order_item_details[:master_sku_code].present?
    else
      child_product_details = get_child_product_details(dpir.child_product_id)

      hsn_numbers << child_product_details[:hsn_number] if child_product_details[:hsn_number].present?
      master_sku_codes << child_product_details[:master_sku_code] if child_product_details[:master_sku_code].present?
    end

    price = price + dpir.amount_payable_by_buyer.to_f.round(2)
    price_per_unit = price_per_unit + (dpir.product_details["price_per_unit"] || dpir.product_details["order_price_per_unit"] || 0.0)
    quantity = quantity + dpir.shipped_quantity
    product_names << dpir.product_details["product_name"]
  end

  argument_params = {
    no_of_packages: no_of_packages,
    hsn_number: hsn_numbers.join(', '),
    master_sku_code: master_sku_codes.join(', '),
    price: price,
    price_per_unit: price_per_unit,
    quantity: quantity,
    product_name: product_names.join(', ')
  }

  items_array = final_items_array_by_no_of_packages(argument_params)

  return items_array
end

def final_items_array_by_no_of_packages(argument_params)
  no_of_packages = argument_params[:no_of_packages].to_i
  counter = 0
  item_quantity_array = []

  while no_of_packages > counter
    quantity = (argument_params[:quantity] / no_of_packages).to_f
    sku = argument_params[:master_sku_code]
    price_per_unit = (argument_params[:price_per_unit] / no_of_packages).to_f
    price = argument_params[:price].to_f
    hsn_code = argument_params[:hsn_number]
    product_name = argument_params[:product_name]

    item_hash = get_item_hash(product_name, quantity, sku, price_per_unit, price, hsn_code)

    item_quantity_array << item_hash
    counter = counter + 1
  end

  return item_quantity_array
end

def items_array_by_dispatch_plan_item_relations
  item_array = []

  @shipment.dispatch_plan_item_relations.each do |dpir|
    hsn_number = ""
    master_sku_code = ""

    if dpir.order_item_id.present?
      order_item_details = get_order_item_details(dpir.order_item_id)

      hsn_number = order_item_details[:hsn_number] if order_item_details[:hsn_number].present?
      master_sku_code = order_item_details[:master_sku_code] if order_item_details[:master_sku_code].present?
    else
      child_product_details = get_child_product_details(dpir.child_product_id)

      hsn_number = child_product_details[:hsn_number] if child_product_details[:hsn_number].present?
      master_sku_code = child_product_details[:master_sku_code] if child_product_details[:master_sku_code].present?
    end

    item_array << items_array(dpir, hsn_number, master_sku_code)
  end

  return item_array.flatten
end

def items_array(dpir, hsn_number, master_sku_code)
  price = dpir.amount_payable_by_buyer.to_f.round(2)
  price_per_unit = dpir.product_details["price_per_unit"] || dpir.product_details["order_price_per_unit"] || 0.0
  quantity = (dpir.shipped_quantity / dpir.pack_size).ceil

  item_quantity_array = []

  while quantity > 0
    pack_size_quantity = dpir.pack_size.to_f
    sku = master_sku_code
    price_per_unit = price_per_unit
    price = price
    hsn_code = hsn_number
    product_name = dpir.product_details["product_name"]

    item_hash = get_item_hash(product_name, pack_size_quantity, sku, price_per_unit, price, hsn_code)

    item_quantity_array << item_hash
    quantity = quantity - 1
  end

  return item_quantity_array
end

def get_item_hash(product_name, quantity, sku, price_per_unit, price, hsn_code)
  item_hash = {
    quantity: quantity.to_i,
    sku: sku,
    description: product_name,
    price: price_per_unit,
    gst_info: {
      consignee_gstin: @shipment.dispatch_plan.destination_address.gstin || "",
      invoice_reference: @invoice_no,
      seller_gstin: @shipment.dispatch_plan.origin_address.gstin,
      enterprise_gstin: @shipment.dispatch_plan.origin_address.gstin,
      is_seller_registered_under_gst: true,
      taxable_value: price.to_f.round(2),
      hsn_code: hsn_code,
      invoice_value: price.to_f.round(2),
      seller_name: only_alphabets(@shipment.dispatch_plan.origin_address.company_name),
      seller_address: @shipment.dispatch_plan.origin_address.street_address,
      seller_state: @shipment.dispatch_plan.origin_address.state,
      seller_pincode: @shipment.dispatch_plan.origin_address.pincode,
      invoice_number: @invoice_no,
      invoice_date: @shipment.created_at.strftime("%Y-%m-%d"),
      sgst_amount: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      cgst_amount: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      igst_amount: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      gst_discount: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      cgst_tax_rate: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      sgst_tax_rate: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      igst_tax_rate: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      gst_total_tax: 0, #for xpressbees static value as these fields are required for Xpressbees order creation
      place_of_supply: "" #for xpressbees static value as these fields are required for Xpressbees order creation
    },
    additional: {
      breadth: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      length: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      height: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
      weight: 10 #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    }
  }
  return item_hash
end

def only_alphabets(string_literal)
  string_literal.gsub(/[^A-Za-z ]/, '').squeeze(' ').strip if string_literal.present?
end
