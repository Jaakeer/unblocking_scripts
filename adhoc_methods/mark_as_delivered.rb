def mark_as_delivered(shipment_ids)
  #shipment_ids = [shipment_id1, shipment_id2, ...]
  counter = 0
  user_responsibility = 0
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    if !shipment.nil?
      counter += 1
      if shipment.cancelled?
        p "#{counter}. ERROR: Shipment(#{shipment_id}) is CANCELLED"
        next
      elsif shipment.status == "delivered"
        p "#{counter}. Shipment(#{shipment_id}) is already Delivered"
        next
      end
      if shipment.dispatched_at.present?
        date = shipment.dispatched_at
      else
        date = DateTime.now
      end
      if changed_transporter(shipment.id)
        begin
          shipment.status = "delivered"
          shipment.delivered_at = date
          shipment.save(validate: false)
          dispatch_plan = shipment.dispatch_plan
          dispatch_plan.status = "done" unless dispatch_plan.status == "done"
          dispatch_plan.save!
          p "#{counter}. Shipment(#{shipment_id}) was marked as delivered"
          if dispatch_plan.dispatch_mode == "seller_to_buyer"
            user_responsibility += 1
          end
        rescue => e
          p "ERROR: Shipment(#{shipment_id}) could not be marked as delivered due to #{e}"
        end
      end
    else
      p "ERROR: Shipment(#{shipment_id}) was not found"
    end
  end
  user_responsibility
end

def changed_transporter(shipment_id)
  shipment = Shipment.find(shipment_id)
  dispatch_plan = shipment.dispatch_plan
  if shipment.company_id == 20694
    shipment.transporter_id = 497 if shipment.transporter_id != 497
    return shipment.save(validate: false)
  elsif [12892, 16130, 15574, 18166].include?(shipment.company_id)
    shipment.transporter_id = 496 if shipment.transporter_id != 496
    return shipment.save(validate: false)
  else
    return false
  end
end
