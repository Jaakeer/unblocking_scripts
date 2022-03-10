data = []
lil_ids.each do |lil_id|
  lil = LotInformationLocation.find(lil_id)
  li = lil.lot_information
  if li.dispatch_plan_item_relation.dispatch_plan.dispatch_mode == "buyer_to_warehouse"
    forward_shipment_id = li.dispatch_plan_item_relation.dispatch_plan.shipment.forward_shipment_id
    forward_shipment = Shipment.find(forward_shipment_id)
    forward_dpir = forward_shipment.dispatch_plan_item_relations.where(master_sku_id: li.master_sku_id).first
    li = nil
    li = forward_dpir.lot_informations.first if forward_dpir.present?
  end
  if li.blank?
    p "LI Not Present LIL: #{lil_id}"
    next
  end
  while li.dispatch_plan_item_relation.dispatch_plan.dispatch_mode != "seller_to_warehouse"
    outward_li = li.dispatch_plan_item_relation.lot_informations.where(inward: false).first
    break if outward_li.nil?
    lot_number = outward_li.lot_number
    li = LotInformation.where(lot_number: lot_number, inward: true, master_sku_id: li.master_sku_id, is_valid: true, lot_infoable_type: "DispatchPlanItemRelation").first
    break if li.blank?
  end
  if li.present? && li.dispatch_plan_item_relation.dispatch_plan.dispatch_mode == "seller_to_warehouse"
    p "Original LIL: #{lil_id}, LI: #{li.id}, Price: #{li.dispatch_plan_item_relation.product_details["price_per_unit"]}"
    data.push([lil_id, li.id, li.dispatch_plan_item_relation.product_details["price_per_unit"]])
  elsif li.present?
    p "Original LIL: #{lil_id}, Just LI: #{li.id}"
  else
    p "Original LIL: #{lil_id}, Not Present"
  end
end
data