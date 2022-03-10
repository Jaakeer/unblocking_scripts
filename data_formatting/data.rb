def cancel_dps(ids)
  ids.each do |id|
    dp = DispatchPlan.find(id)
    s = dp.shipment

    dp.dispatch_plan_item_relations.each do |dpir|
      if dpir.lot_informations.present?
        dpir.lot_informations.each do |li|
          li.invalidate
          li.adjust_warehouse_sku_stocks
        end
      end
    end
    if s.present?
      s.status = "cancelled"
      s.save(validate: false)
    end
    if dp.status != "cancelled"
    dp.status = "cancelled"
    dp.save(validate: false)
    end
    p "#{dp.id} cancelled"
  end
end

def mark_order_items(oi_ids)
  oi_ids.each do |id|
    oi = OrderItem.find(id)
    next if oi.delivery_status == "returned"
    p "--------------------- Starting for OI: #{oi.id}"
    oi.delivery_status = "returned"
    oi.save(validate: false)
    p "Marked returned"
  end
end

def cancel_dp(oi_ids)
  dp_ids = []
     oi_ids.each do |oi_id|
           DispatchPlanItemRelation.where(order_item_id: oi_id).each do |dpir|
               dp = dpir.dispatch_plan
             if dp.dispatch_mode == "warehouse_to_buyer" && dp.status == "open"
               dp_ids.push(dp.id)
       end
          end
     end
    dp_ids.uniq
end

DispatchPlan.where("cast(origin_address_snapshot::json->>'centre_id' as int) = 19302").each do |dp|
s = dp.shipment
direct_order_ids.push(s.direct_order_id)
end

direct_order_ids.each do |id|
dor = DirectOrder.find(id)
dor.status = "returned"
dor.save(validate: false) unless DirectOrder.find(id).status == "returned"
dor.order_items.each do |oi_id|
oi = OrderItem.find(oi_id)
if oi.delivery_status == "returned"
order_item_ids.push(oi_id)
else
oi.delivery_status = "returned"
oi.save(validate: false)
order_item_ids.push(oi_id)
end
end
end