def increase_po_quantity(po_id, po_data)
  ppo = BizongoPurchaseOrder.find(po_id)
  po_data.each do |ref|
    oi_id = ref[0]
    qty = ref[1]
    ppo.bizongo_po_items.where(order_item_id: oi_id).first.update(total_quantity: qty)
  end
end

def increase_dp_quantity(dp_id, sku_data)
  sku_data.each do |ref|
    sku_id = ref[0]
    qty = ref[1]
    DispatchPlan.find(dp_id).dispatch_plan_item_relations.where(master_sku_id: sku_id).first.update(quantity: qty, expected_shipped_quantity: qty)
  end
end