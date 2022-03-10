#input = [[shipment_id, "tracking_id"], [shipment_id, "tracking_id"],...]
def change_tracking_id(shipment_data)
  shipment_data.each do |ref|
    dispatch_plan_id = ref[0]
    tracking_id = ref[1].to_s
    shipment = Shipment.where(dispatch_plan_id: dispatch_plan_id).first
    if shipment.present? && shipment.tracking_id != tracking_id
      current_tracking_id = shipment.tracking_id
      shipment.tracking_id = tracking_id
      shipment.clickpost_tracking_id = tracking_id
      shipment.save!
      p "Tracking for Shipment ID: #{dispatch_plan_id} has been changed to #{tracking_id} from #{current_tracking_id}"
    elsif shipment.present?
      p "Tracking for Dispatch Plan ID: #{dispatch_plan_id} is already #{tracking_id}"
    else
      p "Shipment could not be found"
    end
  end
end
