#Run this after you have closed all POs.

#clean up for W-B and W-W DPs which are not being fulfilled and are being cleaned up for BARS to function properly.
#Publish the returned processed_sp list with all for the update on the status of the clean up
def cancel_dispatch_plans(order_item_ids)
    processed_dps = Hash.new
    dispatch_plan_ids = DispatchPlanItemRelation.where(order_item_id: order_item_ids).map(&:dispatch_plan_ids).uniq
    dispatch_plan_ids.each do |dp_id|
        dp = DispatchPlan.find(dp_id)
        next if dp.status == "cancelled" || dp.nil?
        if dp.shipment.blank? && (dp.dispatch_mode == "warehouse_to_buyer" || dp.dispatch_mode == "warehouse_to_warehouse")
            if dp.pick_list_file.present?
                p "Pick List has been generated for the DP: #{dp_id}"
                processed_dps[dp_id] = "PickList already generated"
            else
                begin
                    dp.status = "cancelled"
                    dp.save(validate: false)
                    p "DP #{dp_id} has been #{dp.status}"
                    processed_dps[dp_id] = "Cancelled"
                rescue => e
                    p "Something went wrong with #{dp_id}: #{e}"
                    processed_dps[dp_id] = "LI and LIL could not be invalidated"
                end
            end
        elsif dp.shipment.blank?
            p "DP: #{dp_id}, is not warehouse to buyer or warehouse to warehouse it's #{dp.dispatch_mode}"
        else
            p "Shipment (#{dp.shipment.id})is already created for the DP: #{dp_id}"
            processed_dps[dp_id] = "Shipment Created: #{dp.shipment.id}"
        end
    end
    processed_dps
end


