dp_ids.each do |dp_id|
dp = DispatchPlan.find(dp_id)
next if dp.status == "cancelled"
shipment = dp.shipment
if shipment.present? && shipment.status == "ready_to_ship"
shipment.status = "cancelled"
shipment.cancelled_at = DateTime.now
shipment.save!
p"cancelled #{dp_id}"
elsif shipment.nil? || shipment.status == "cancelled"
  dp.status = "cancelled"
  dp.save!
  p"cancelled #{dp_id}"
end
end
