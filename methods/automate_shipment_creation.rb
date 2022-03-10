#dispatch_plans = [dp_id1, dp_id2, dp_id3,....]
def create_shipments(dispatch_plans)
  shipment_created = Hash.new
  dispatch_plan_ids  = dispatch_plans.uniq
  dispatch_plan_ids.each do |dispatch_plan_id|
    start_time = Time.now.to_i
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    if dispatch_plan.shipment.present?
      p "Shipment Already present: #{dispatch_plan.shipment.id} for DP: #{dispatch_plan_id}"
      shipment_created[dispatch_plan_id] = "Already Present #{dispatch_plan.shipment.id}"
    else
      add_id = dispatch_plan.destination_address_id
      add = Address.find(add_id)
      change_pack_size(dispatch_plan)
      if add.gstin.nil?
        add.gstin = "06AABCU7755Q1ZK"
        add.save(validate: false)
        dispatch_plan.destination_address_id = add_id + 1
        dispatch_plan.save(validate: false)
        dispatch_plan.destination_address_id = add_id
        dispatch_plan.save(validate: false)
      end
      if dispatch_plan && dispatch_plan.origin_address && dispatch_plan.origin_address.warehouse
        service = ShipmentServices::AutoShipmentCreationForWToBDispatches.new({dispatch_plan_id: dispatch_plan_id})
        service.execute!
      end
      if Shipment.where(dispatch_plan_id: dispatch_plan_id).present?
        s_id = Shipment.where(dispatch_plan_id: dispatch_plan_id).first.try(:id)
        end_time = Time.now.to_i
        p "Shipment created: #{s_id} for DP ID: #{dispatch_plan_id}. Execution time = #{end_time - start_time}"
        shipment_created[dispatch_plan_id] = "#{s_id}"
      else
        end_time = Time.now.to_i
        p "Shipment couldn't be created for DP ID: #{dispatch_plan_id}. Execution time = #{end_time - start_time}"
        shipment_created[dispatch_plan_id] = "No Shipment"
      end
    end
  end
  shipment_created
end

def change_pack_size(dispatch_plan)
  dispatch_plan.dispatch_plan_item_relations.each do |dpir|
    if dpir.pack_size == 1 || dpir.pack_size.nil?
      dpir.pack_size = dpir.quantity
      dpir.save(validate: false)
    end
  end
end

def fix_pack_size(dispatch_plans)
  dispatch_plans.each do |dp_id|
    dp = DispatchPlan.find(dp_id)
    if dp.shipment.present?
      result = false
      shipment = dp.shipment
      #Shipment Number of packages changed to 1
      shipment.no_of_packages = 1
      if !shipment.save(validate: false)
        dp.dispatch_plan_item_relations.each do |dpir|
          if dpir.pack_size == 1 || dpir.pack_size.nil?
            dpir.pack_size = dpir.quantity
            result = dpir.save(validate: false)
          end
        end
      else
        result = true
      end
      if result
        p "_________ Running Clickpost Job _________"
        result = CreateOrderToClickpostJob.perform_now(shipment.id)
        if result.nil?
          p "xxxxxxxx Packaging label could not be generated for DP: #{dp.id}"
        else
          p "+++++++++ Packaging Label generated and address is fixed for DP: #{dp.id}"
        end
      end
    else
      p "Shipment Doesn't exist for DP #{dp.id}"
    end
  end
end



def fix_gstin(dp_id)
    dp = DispatchPlan.find(dp_id)
    add_id = dp.destination_address_id
    add = Address.find(add_id)
    if add.gstin.nil?
      add.gstin = "06AABCU7755Q1ZK"
      add.save(validate: false)
    end
    if dp.shipment.present?
      #This is just to refresh the address snapshot
      #Can't use UpdateDpPriceJob as we don't want to update the invoice file
      dp.destination_address_id = add_id + 1
      dp.save(validate: false)
      dp.destination_address_id = add_id
      dp.save(validate: false)

      shipment_id = dp.shipment.id
      if dp.shipment.packaging_labels.nil?
        p "_________ Running Clickpost Job _________"
        result = CreateOrderToClickpostJob.perform_now(shipment_id)
        if result.nil?
          p "xxxxxxxx Packaging label could not be generated for DP: #{dp_id}"
        else
          add.gstin = nil
          add.save(validate: false)
          p "+++++++++ Packaging Label generated and address is fixed for DP: #{dp_id}"
        end
      else
        p "+++++++++ Packaging Label already exist and address is fixed for DP: #{dp_id}"
        add.gstin = nil
        add.save(validate: false)
      end
    else
      p "xxxxxxxx Shipment couldn't be created for Dispatch Plan: #{dp_id}"
      add.gstin = nil
      add.save(validate: false)
    end
end

def update_tracking_data(tracking_data)
  counter = 0
  tracking_data.each do |tracking|
    tracking_id = tracking[0]
    dp_id = tracking[1]
    counter += 1
    shipment = DispatchPlan.find(dp_id).shipment
    if shipment.nil?
      p "No Shipment found for Dispatch Plan #{dp_id}, Coutner: #{counter}"
    elsif shipment.tracking_id == tracking_id
      p "Tracking already present for Shipment: #{shipment.id}, Counter: #{counter}"
    else
      shipment.tracking_id = tracking_id
      shipment.clickpost_tracking_id = tracking_id
      p "Shipment Tracking updated for #{shipment.id}, Counter: #{counter}" if shipment.save(validate: false)
    end
  end
end


