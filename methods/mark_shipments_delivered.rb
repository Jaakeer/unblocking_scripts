73986, 74576, 75191, 76563, 77184, 81489, 83785, 83914, 83979, 84906, 84911, 84914, 84965, 85230, 85236, 85311, 86336, 87890, 88669, 88885, 89368


#input = [[shipment_id, "delivery_date"], [shipment_id1, "delivery_date1"], ....]

def mark_shipments_delivered(shipment_data)
    seller_to_buyer_shipments = []
    shipment_data.each do |shipment_delivery|
        shipment = Shipment.find(shipment_delivery[0])
        delivery_date = shipment_delivery[1]
        if shipment.dispatch_plan.dispatch_mode == "seller_to_warehouse" && shipment.status == "dispatched"
            shipment.status = "delivered"
            shipment.delivered_at = delivery_date
            shipment.save(validate: false)
        elsif shipment.dispatch_plan.dispatch_mode == "seller_to_buyer" && shipment.status == "dispatched"
            p "Shipment #{shipment.id} is Seller to Buyer, please review buyer payment status before running the script. Adding shipment IDs to seller_to_buyer_shipments"
            seller_to_buyer_shipments.push(shipment.id)
        else
            p "#{shipment.id} Shipment is in #{shipment.status} state."
        end
    end
    return seller_to_buyer_shipments if seller_to_buyer_shipments.present?
end


counter = 1
ticker = 1
DispatchPlan.where("cast(destination_address_snapshot::json->>'centre_id' as int) = 19302").each do |dp|
    next if dp.shipment.nil?
    s = dp.shipment
    next if s.status != "dispatched"
    if s.dispatched_at.nil? && s.status == "dispatched"
      dispatch_date = DateTime.now - 5.days
      success = s.update(dispatched_at: dispatch_date)
      p "#{counter}. Shipment Dispatch date not present changed it to #{s.dispatched_at}" if success
      counter +=1
    else
      p "#{ticker}. Dispatch date already exists ID: #{s.id} dispatched_at: #{s.dispatched_at}"
      ticker +=1
    end
end
