def cancel_dispatch_plans(dispatch_plans, cancel)
    result_list = Hash.new
    dispatch_plans = dispatch_plans.uniq
    counter = 1
      dispatch_plans.each do |dispatch_plan_id|
          dispatch_plan = DispatchPlan.find(dispatch_plan_id)
          next if dispatch_plan.status == "cancelled" || dispatch_plan.nil?

          p "#{counter}. Starting with #{dispatch_plan_id}, current status: #{dispatch_plan.status}"
          if dispatch_plan.shipment.present?
            if cancel
              if cancel_shipment(dispatch_plan)
                cancel_dp(dispatch_plan)
                result_list[dispatch_plan_id] = "Shipment: #{dispatch_plan.shipment.id} Cancelled"
              end
            else
              puts "There is a shipment #{dispatch_plan.shipment.id} present for #{dispatch_plan_id}"
              result_list[dispatch_plan_id] = "Shipment: #{dispatch_plan.shipment.id}"
            end
          elsif !dispatch_plan.pick_list_file.nil?
            w = WarehouseServices::PickList.new
            w.cancel_pick_list(dispatch_plan.id)
              p "The pick list is already generated for the DP ID #{dispatch_plan_id}"
              p "Cancelling Pick list"
              cancel_dp(dispatch_plan)
              result_list[dispatch_plan_id] = "PickList exist and cancelled"
          else
            begin
              dispatch_plan.status = "cancelled"
              if dispatch_plan.save(validate: false)
                  p "Dispatch Plan #{dispatch_plan.id} is cancelled successfully"
                  result_list[dispatch_plan_id] = "Cancelled"
              end
            rescue => e
              p "Something went wrong: #{e}"
              result_list[dispatch_plan_id] = "Something went wrong: check logs"
            end
          end
          counter = counter + 1
      end

    return result_list if result_list.present?
end

def cancel_shipment(dispatch_plan)
  shipment = dispatch_plan.shipment
  if shipment.status == "cancelled"
    p "Shipment with ID: #{shipment.id} already cancelled"
    return true
  elsif shipment.status == "ready_to_ship"
    p "Cancelling shipment with ID: #{shipment.id}"
    begin
    shipment.status = "cancelled"
    return shipment.save(validate: false)
    rescue =>e
      p "Shipment could not be cancelled due to #{e}"
    end
  else
    p "Shipment (#{shipment.id}) is not in 'Read to Ship' status"
    return  false
  end
end

def cancel_dp(dispatch_plan)
  if !dispatch_plan.cancelled?
    begin
    dispatch_plan.status = "cancelled"
    dispatch_plan.save(validate: false)
    p "DP: #{dispatch_plan.id} is cancelled"
    rescue =>e
      p "DP could not be cancelled due to #{e}"
    end
  end
end

#### BIZONGO BACKEND
def cancel_dor(dor_ids)
  counter = 1
  dor_ids.each do |dor_id|
    dor = DirectOrder.find(dor_id)
    p "#{counter}. Starting with DOR: #{dor_id}"
    begin
      dor.status = "cancelled"
      dor.save(validate: false)
      dor.order_items.each do |oi|
        next if oi.delivery_status == "cancelled"
        oi.delivery_status = "cancelled"
        oi.save(validate: false)
      end
      p ":::CANCELLED:::"
    rescue => e
      p "XXX::ERROR: #{e}::XXX"
    end
    counter = counter + 1
  end
end