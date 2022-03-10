def manage_li(dp_ids)
  lot_numbers = delete_all_li(dp_ids)
  final_data = check_inward_li(lot_numbers)
  if final_data.present?
    p "Check properly...."
  end
  return final_data
end

def delete_all_li(dp_ids)
  lot_numbers = []
  DispatchPlanItemRelation.where(dispatch_plan_id: dp_ids).each do |dpir|
    if dpir.lot_informations.present?
      dpir.lot_informations.each do |li|
        li.lot_information_locations.each do |lil|
          lil.delete
        end

        lot_numbers.push(li.lot_number)
        li.delete
      end
    end
  end
  return lot_numbers.uniq
end

def check_inward_li(lot_numbers)
  wrong_lis = []
  lot_numbers.each do |lot_number|
    count = LotInformation.where(lot_number: lot_number).count
    if count > 1
      wrong_lis.push(lot_number, count)
    end
  end
  return wrong_lis
end

data = []
shipment_ids.each do |id|
  Shipment.find(id).dispatch_plan_item_relations.each do |dpir|
    data.push([dpir.id, dpir.order_item_id])
  end
end

dg_ids = []
po_ids.each do |po_id|
  po = PurchaseOrder.find(po_id)
  dg_ids.push(po.delivery_groups.map(&:id))
end

multiple_dg_id = []
dg_ids.each do |dg_id|
  gd = DeliveryGroup.find(dg_id)
  gd_quantity = gd.delivery_request_items.map(&:quantity).sum()
  dors = DirectOrder.where(delivery_group_id: gd.id)
  order_items = OrderItem.where(direct_order_id: dors.map(&:id))
  dor_quantity = order_items.map{ |oi| oi.total_quantity }.sum()
  if dor_quantity != gd_quantity
    multiple_dg_id << gd.id
  end
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

    item_array << items_array(dpir, hsn_number, master_sku_code, shipment)
  end


  return item_array.flatten.uniq
end

def items_array(dpir, hsn_number, master_sku_code, shipment)
  price = dpir.amount_payable_by_buyer.to_f.round(2)
  price_per_unit = dpir.product_details["price_per_unit"] || dpir.product_details["order_price_per_unit"] || 0.0
  quantity = (dpir.shipped_quantity/dpir.pack_size.to_f).ceil

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

def get_item_hash(shipment, quantity, sku, description_counter, price_per_unit, price, hsn_code)
  item_hash = {
      quantity: quantity.to_i,
      sku: sku,
      description: "Cartoon Box #{description_counter}",
      price: price_per_unit,
      gst_info: {
          consignee_gstin: shipment.dispatch_plan.destination_address.gstin,
          invoice_reference: nil,
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
          invoice_number: shipment.buyer_invoice_no,
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

def cancel_dors(po_ids)
  uncancelled_dors = []
  order_item_ids = []
  uncancelled_prs = []
  delivery_groups = DeliveryGroup.where(purchase_order_id: po_ids)
  delivery_groups.each do |delivery_group|
    if delivery_group.seller_po_requests.present?
      p "Deleting SellerPORequests for the delivery group"
      delivery_group.seller_po_requests.each do |pr|
        next if pr.status == "cancelled"
        child_product_relations = pr.seller_po_request_child_product_relations
        seller_po_versions = pr.seller_po_request_versions
        if child_product_relations.present? && seller_po_versions.present? && pr.seller_po_request_bizongo_po_relations.blank?
          p "Destroying all records for PR: #{pr.id}"
          unless pr.save(validate: false)
            p "PR: #{pr.id} could not be cancelled"
            uncancelled_prs.push(pr.id)
          end
        else
          p "PR: #{pr.id} could not cancelled as it has a PO"
          uncancelled_prs.push(pr.id)
        end
      end
    end

    delivery_group.direct_orders.each do |dor|
      order_item_ids.push(dor.order_items.map(&:id))
      begin
        next if dor.status == "cancelled"
        p "Cancelling #{dor.id}...."
        dor.status = "cancelled"
        unless dor.save!
          p "DOR: #{dor.id} couldn't be cancelled"
          uncancelled_dors.push(dor.id)
        end
      rescue => e
        p "DOR: #{dor.id} couldn't be cancelled because of #{e}"
        uncancelled_dors.push(dor.id)
      end
    end
  end
  return order_item_ids.flatten.uniq, uncancelled_dors.uniq, uncancelled_prs.uniq
end

def cancel_dps(order_item_ids)
  dp_ids = []
  non_cancelled_dps = []
  order_item_ids.each do |order_id|
    dp_ids.push(DispatchPlanItemRelation.where(order_item_id: order_id).map(&:dispatch_plan_id))
  end
  dp_ids = dp_ids.flatten.uniq
  dp_ids.each do |dp_id|
    dp = DispatchPlan.find(dp_id)
    next if dp.status == "cancelled"
    if dp.shipment.blank?
      p "Starting to cancel DP: #{dp_id}"
      dp.status == "cancelled"
      if dp.save
        p "DP: #{dp_id} cancelled sucessfully"
      else
        p "DP: #{dp_id} could not be cancelled"
        non_cancelled_dps.push(dp_id)
      end
    else
      p "DP: #{dp_id} already has a shipment: #{dp.shipment.id}"
      non_cancelled_dps.push(dp_id)
    end
  end
  return non_cancelled_dps
end

def cancel_prs(pr_ids)
  uncancelled_prs = []
  prs = SellerPoRequest.where(id: pr_ids)
  cancel_pr = false
  prs.each do |pr|
    next if pr.status == "cancelled"
    seller_po_relations = pr.seller_po_request_bizongo_po_relations
    seller_po_relations.each do |seller_po_relation|
      ppo_id = seller_po_relation.bizongo_purchase_order_id
      ppo = BizongoPurchaseOrder.find(ppo_id)
      if ppo.status = "pending"
        ppo.status = "cancelled"
        if ppo.save(validate: false)
          cancel_pr = true
        else
          p "PO: #{ppo.id} could not be cancelled"
          cancel_pr = false
        end
      elsif ppo.status == "cancelled"
        p "Already Cancelled"
        cancel_pr = false
      else
        p "PO: #{ppo_id} could not be cancelled because it's in #{ppo.status} state"
        cancel_pr = false
      end
    end
    if cancel_pr
      pr.status = "cancelled"
      unless pr.save(validate: false)
        p "PR: #{pr.id} could not be cancelled"
        uncancelled_prs.push(pr.id)
      end
    else
      p "PR: #{pr.id} could not be cancelled"
      uncancelled_prs.push(pr.id)
    end
  end
  uncancelled_prs
end

def change_pack_size(codes)
  codes.each do |code|
    sku = MasterSku.where(sku_code: code).first
    sku.products.each do |product|
      product.pack_size = 1
      product.save(validate: false)
      matrices = product.product_matrices
      matrices.each do |matrix|
          matrix.value = "1"
          matrix.save(validate: false)
      end
    end
  end
end

def reopen_shipments(shipment_ids)
  change_status = false
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    next if shipment.status == "delivered"
    shipment.dispatch_plan_item_relations.each do |dpir|
      if revalidate_li(dpir)
        change_status = true
      else
        change_status = false
      end
    end
    if change_status
      p "Changing status for shipment #{shipment.id}"
      shipment.status = "delivered"
      if shipment.save(validate: false)
        dp = shipment.dispatch_plan
        dp.status = "done"
        dp.save(validate: false)
        p "Shipment status changed successfully"
      else
        p "Shipment status could not be changed"
      end
    else
      p "Stocks could not be adjusted for #{shipment.id}"
    end
  end
end

def revalidate_li(dpir)
  adjustments = []
  all_good = false
  all_good_stocks = false
  dpir.lot_informations.valid_records.each do |li|
    lil_data = []
    lot_number = li.lot_number
    li.lot_information_locations.each do |lil|
      location_id = lil.location_id
      quantity = lil.quantity
      lil_data.push([location_id, quantity])
    end
    adjustments.push([lot_number,lil_data])
    all_good_stocks = fix_stocks(adjustments)
    if all_good_stocks
      all_good = validate_li(li)
    else
      li.is_valid = false
      li.save
      li.lot_information_locations.each do |lil|
        lil.is_valid = false
        lil.save
      end
      all_good = false
    end
  end
  return all_good
end

def validate_li(li)
  li.lot_information_locations.each do |lil|
    lil.is_valid = true
    lil.save
  end
  li.is_valid = true
  return li.save
end

def fix_stocks(adjustments)
  all_adjusted = false
  adjustments.each do |adjustment|
    lot_number = adjustment[0]
    lil_data = adjustment[1]
    lot_information = LotInformation.where(lot_number: lot_number, inward: true, is_valid: true).first
    if lot_information.present?
      lot_information.lot_information_locations.each do |lil|
        lil_data.each do |ref_lil|
          location_id = ref_lil[0]
          quantity = ref_lil[1]
          if lil.location_id = location_id && lil.remaining_quantity > quantity
            lil.remaining_quantity -= quantity
            if lil.save
              all_adjusted = true
            end
          else
            p "LIL remaining quantity #{lil.remaining_quantity} is not enough in LotInfoLocation: #{lil.id}, reference data was #{lot_number}, #{ref_lil}"
            all_adjusted = false
          end
        end
      end
    else
      p "LotInformation not found against lot number: #{lot_number}"
    end
  end
  return all_adjusted
end

#dp_data = [dp1, dp2]
#sku_data = [[child_sku, multiplier], [child_sku, multiplier],....]

def fix_numbers(dp_data, sku_data)
  dp_data.each do |dp_id|
    dp = DispatchPlan.find(dp_id)
    sku_data.each do |sku_multiplier|
      sku_id = sku_multiplier[0]
      multiplier = sku_multiplier[1]
      if multiplier > 1
        li = dp.dispatch_plan_item_relations.first.lot_informations.where(is_valid: true, master_sku_id: sku_id).first
        lil = li.lot_information_locations.first
        lot_number = li.lot_number
        inward_lil = LotInformation.where(is_valid: true, master_sku_id: sku_id, inward: true, lot_number: lot_number).first.lot_information_locations.first
        current_qty = li.quantity
        li.quantity = li.quantity * multiplier
        li.save
        lil.quantity = li.quantity
        lil.save
        inward_lil.remaining_quantity = inward_lil.remaining_quantity - (li.quantity - current_qty)
        inward_lil.save
      end
    end
  end
end