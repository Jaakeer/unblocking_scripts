def find_dors

end

def find_oi(oi_ids)
  blank_oi_ids = []
  ww_oi_ids = []
  dp_ids = []
  oi_ids.each do |oi_id|
    if DispatchPlanItemRelation.where(order_tracking_id: oi_id).present? || DispatchPlanItemRelation.where(order_item_id: oi_id).present?
      dpir = DispatchPlanItemRelation.where(order_tracking_id: oi_id).first
      dp = dpir.dispatch_plan
      if dp.dispatch_mode == "warehouse_to_warehouse"
        p "DP ID: #{dp.id}"
        dp_ids.push(dp.id)
        ww_oi_ids.push(oi_id)
      end
    else
      p "No DP found for order item #{oi_id}"
      blank_oi_ids.push(oi_id)
    end
  end
  blank_oi_ids
  ww_oi_ids
  dp_ids
end

oi_ids = []
pos.each do |po_id|
  po = PurchaseOrder.find(po_id)
  m = po.direct_orders.map(&:status)
  po.direct_orders.each do |dor|
    if dor.status == "pending"
      p "#{dor.id}"
      oi_ids.push(dor.order_items.map(&:id))
    end
  end
end