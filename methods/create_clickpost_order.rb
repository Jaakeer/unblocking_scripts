def create_order(shipment_id)
  shipment = Shipment.find(shipment_id)
  params = create_order_creation_params(shipment)
  params
end

def create_order_creation_params(shipment)
  if shipment.invoice.present? && shipment.invoice.dc?
    @invoice_no = shipment.buyer_delivery_challan_no
    @invoice_no = shipment.return_delivery_challan_no if !@invoice_no && shipment.dispatch_plan.is_return_type?
  else
    @invoice_no = shipment.buyer_invoice_no
  end

  @request_params = {
      shipment_details:{
          cod_value: 00,
          invoice_date: shipment.invoice.buyer_invoice_date.strftime("%Y-%m-%d"),
          order_type: "PREPAID",
          invoice_number: @invoice_no,
          invoice_value: shipment.total_buyer_invoice_amount.to_f.round(2),
          shipment_type: "MPS",
          breadth: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
          length: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
          height: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
          weight: 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
          items: get_item_details(shipment)
      },
      pickup_info: get_pick_up_info(shipment),
      drop_info: get_drop_info(shipment),
      courier_partner: shipment.transporter.clickpost_cp_id,
      reference_number: shipment.id.to_s,
      weight: shipment.weight,
      additional: {
          label: true,
          data_validation: true,
          delivery_type: "FORWARD",
          account_code: shipment.transporter.clickpost_account_code,
          return_info: {
              email: @seller_email || "support@clickpost.in",
              name: shipment.dispatch_plan.origin_address.company_name,
              phone: shipment.dispatch_plan.origin_address.mobile_number,
              address: shipment.dispatch_plan.origin_address.street_address,
              country: shipment.dispatch_plan.origin_address.country,
              city: shipment.dispatch_plan.origin_address.city,
              pincode: shipment.dispatch_plan.origin_address.pincode,
              state: shipment.dispatch_plan.origin_address.state,
          }
      }
  }
  @request_params
end

def get_pick_up_info(shipment)
  pickup_info = {
      pickup_time: shipment.created_at.iso8601,
      email: @seller_email || "support@clickpost.in",
      pickup_address: shipment.dispatch_plan.origin_address.street_address,
      pickup_state: shipment.dispatch_plan.origin_address.state,
      pickup_name: shipment.dispatch_plan.origin_address.company_name,
      pickup_country: shipment.dispatch_plan.origin_address.country,
      tin: shipment.dispatch_plan.origin_address.gstin,
      pickup_city: shipment.dispatch_plan.origin_address.city,
      pickup_phone: shipment.dispatch_plan.origin_address.mobile_number,
      pickup_pincode: shipment.dispatch_plan.origin_address.pincode
  }

  return pickup_info
end

def get_drop_info(shipment)
  drop_info = {
      drop_country: shipment.dispatch_plan.destination_address.country,
      drop_city: shipment.dispatch_plan.destination_address.city,
      drop_phone: shipment.dispatch_plan.destination_address.mobile_number,
      drop_address: shipment.dispatch_plan.destination_address.street_address,
      drop_name: shipment.dispatch_plan.destination_address.company_name,
      drop_state: shipment.dispatch_plan.destination_address.state,
      drop_pincode: shipment.dispatch_plan.destination_address.pincode,
      drop_email: @buyer_email || "support@clickpost.in"
  }

  return drop_info
end

def get_item_details(shipment)
  items_array = []

  no_of_packages = shipment.no_of_packages

  if no_of_packages >= 1.0
    items_array = items_array_by_no_of_packages(shipment, no_of_packages)
  else
    items_array = items_array_by_dispatch_plan_item_relations(shipment)
  end

  return items_array
end

def get_order_item_details(order_item_id)
  order_item_response = Bizongo::Communicator.order_items_index!({ids: [order_item_id], invoice_response: true})
  order_item = order_item_response[:order_items].first
  seller_email = nil
  buyer_email = nil

  @seller_email = order_item_response[:seller_company][:primary_contact][:email] if order_item_response[:seller_company].present? && order_item_response[:seller_company][:primary_contact].present? && order_item_response[:seller_company][:primary_contact][:email].present?

  @buyer_email = order_item_response[:direct_order][:buyer][:email] if order_item_response[:direct_order].present? && order_item_response[:direct_order][:buyer].present? && order_item_response[:direct_order][:buyer][:email].present?

  order_item_hash = {
      hsn_number: order_item[:hsn_number],
      master_sku_code: order_item[:master_sku_code]
  }

  return order_item_hash
end

def get_child_product_details(child_product_id)
  child_product_response = Bizongo::Communicator.child_products_index!({ids: [child_product_id]})
  child_product = child_product_response[:child_products].first

  child_product_hash = {
      hsn_number: child_product[:hsn_number],
      master_sku_code: child_product[:sku_code]
  }

  return child_product_hash
end

def items_array_by_no_of_packages(shipment,no_of_packages)
  hsn_numbers = []
  master_sku_codes = []
  price = 0.0
  price_per_unit = 0.0
  quantity = 0.0

  shipment.dispatch_plan_item_relations.each do |dpir|
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
  end

  argument_params = {
      no_of_packages: no_of_packages,
      hsn_number: hsn_numbers.join(', '),
      master_sku_code: master_sku_codes.join(', '),
      price: price,
      price_per_unit: price_per_unit,
      quantity: quantity
  }

  items_array = final_items_array_by_no_of_packages(shipment, argument_params)

  return items_array
end

def final_items_array_by_no_of_packages(shipment, argument_params)
  no_of_packages = argument_params[:no_of_packages].to_i
  counter = 0
  item_quantity_array = []

  while no_of_packages > counter
    quantity = (argument_params[:quantity]/no_of_packages).to_f
    sku = argument_params[:master_sku_code]
    description_counter = counter + 1
    price_per_unit = (argument_params[:price_per_unit]/no_of_packages).to_f
    price = (argument_params[:price]/no_of_packages).to_f
    hsn_code = argument_params[:hsn_number]

    item_hash = get_item_hash(shipment, quantity, sku, description_counter, price_per_unit, price, hsn_code)

    item_quantity_array << item_hash
    counter = counter + 1
  end

  return item_quantity_array
end

def items_array_by_dispatch_plan_item_relations(shipment)
  item_array = []

  shipment.dispatch_plan_item_relations.each do |dpir|
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

    item_array << items_array(shipment, dpir, hsn_number, master_sku_code)
  end

  return item_array.flatten
end

def items_array(shipment, dpir, hsn_number, master_sku_code)
  price = dpir.amount_payable_by_buyer.to_f.round(2)
  price_per_unit = dpir.product_details["price_per_unit"] || dpir.product_details["order_price_per_unit"] || 0.0
  quantity = 1

  item_quantity_array = []

  while quantity > 0
    pack_size_quantity = dpir.pack_size.to_f
    sku = master_sku_code
    description_counter = dpir.id
    price_per_unit = price_per_unit
    price = price
    hsn_code = hsn_number

    item_hash = get_item_hash(shipment, pack_size_quantity, sku, description_counter, price_per_unit, price, hsn_code)

    item_quantity_array << item_hash
    quantity = quantity - 1
  end

  return item_quantity_array
end


def get_item_hash(shipment, quantity, sku, description_counter, price_per_unit, price, hsn_code)
  if shipment.invoice.present? && shipment.invoice.dc?
    @invoice_no = shipment.buyer_delivery_challan_no
    @invoice_no = shipment.return_delivery_challan_no if !@invoice_no && shipment.dispatch_plan.is_return_type?
  else
    @invoice_no = shipment.buyer_invoice_no
  end
  item_hash = {
      quantity: quantity.to_i,
      sku: sku,
      description: "Cartoon Box #{description_counter}",
      price: price_per_unit,
      gst_info: {
          consignee_gstin: shipment.dispatch_plan.destination_address.gstin,
          invoice_reference: @invoice_no,
          seller_gstin: shipment.dispatch_plan.origin_address.gstin,
          enterprise_gstin: shipment.dispatch_plan.origin_address.gstin,
          is_seller_registered_under_gst: true,
          taxable_value: price.to_f.round(2),
          hsn_code: hsn_code,
          invoice_value: price.to_f.round(2),
          seller_name: shipment.dispatch_plan.origin_address.company_name,
          seller_address: shipment.dispatch_plan.origin_address.street_address,
          seller_state: shipment.dispatch_plan.origin_address.state,
          seller_pincode: shipment.dispatch_plan.origin_address.pincode,
          invoice_number: @invoice_no,
          invoice_date: shipment.invoice.buyer_invoice_date.strftime("%Y-%m-%d"),
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

