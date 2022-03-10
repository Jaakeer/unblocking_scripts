def mark_timeline_done(shipments)
  for i in shipments do
    shipment = Shipment.find(i)
    if shipment.status = "delivered"
      timeline = shipment.dispatch_plan.timelines.sort.first
      if timeline.timeline_type = "delivery"
        timeline.status = "done"
        timeline.save!
        puts "Timeline marked as done"
      else
        puts "Timeline is Delivery, please check and try again"
        puts shipment.dispatch_plan.id
      end
    else
      puts shipment.id
      puts "Shipment not delivered yet"
    end
  end
end