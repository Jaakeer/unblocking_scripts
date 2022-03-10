def close_all_dors(direct_order_ids)
  non_cancelled_dors = Hash.new
  adjusted_dors = Hash.new
  direct_order_ids.each do |dor_id|
    dor = DirectOrder.find(dor_id)
    dor.status = "pending"
    dor.save(validate: false)
    p "DOR: #{dor_id} is currently #{dor.status}"
    begin
      service = DirectOrderServices::CancelDirectOrder.new dor_id
      result = service.execute
      if service.errors.present?
        p "DOR couldn't be cancelled or closed due to #{service.errors}"
        non_cancelled_dors[dor_id] = service.errors
      else
        adjusted_dors[dor_id] = "DOR successfully processed"
        p "DOR: #{dor.id} is processed"
        cancel_dor = true
        dor.order_items.each do |oi|
          if oi.delivery_status != "cancelled"
            cancel_dor = false
          end
        end
        if cancel_dor

          dor.status = "cancelled"
          dor.save!
          p "DOR: #{dor.id} is cancelled"
        else
          p "DOR: #{dor.id} is fine, and will not be cancelled"
        end
      end
    rescue => e
      p "------------------Error while fetching data: #{e}-----------------"
      non_cancelled_dors[dor_id] = e
    end
  end
  [non_cancelled_dors, adjusted_dors]
end

def cancel_shipments(shipment_ids)
  dor_ids = []
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    p "Starting with shipment: #{shipment.id}"
    dor_id = shipment.direct_order_id
    if shipment.status = "ready_to_ship"
      shipment.status = "cancelled"
      if shipment.save(validate: false)
        p "Shipment successfully cancelled, DOR ID pushed in the list.."
        dor_ids.push(dor_id)
        dp = shipment.dispatch_plan
        if dp.status != "cancelled"
          p "DP was not cancelled automatically, cancelling DP now.."
          dp.status = "cancelled"
          dp.save!
        end
      end
    else
      p "Shipment couldn't be cancelled, shipment status: #{shipment.status}, DOR ID: #{shipment.direct_order_id}"
    end
  end
  return dor_ids.uniq
end

dor_ids.each do |dor_id|
  dor = DirectOrder.find(dor_id)
  p "Starting with direct order: #{dor_id}"
  dor.status = "cancelled"
  if dor.save(validate: false)
  p "Direct Order Cancelled"
    dor.order_items.each do |oi|
      if oi.delivery_status != "cancelled"
        oi.delivery_status = "cancelled"
        oi.save(validate: false)
      end
    end
  end
end

def fix_addresses(address_ids)
  address_ids.each do |address_id|
    address = Address.find(address_id)
    next if address.nil?
    pincode = address.pincode
    if BizongoPincode.where(pincode: pincode).present?
      state = BizongoPincode.where(pincode: pincode).last.state
      address.state = state
      address.save
    end
  end
end

def change_transporter(dp_ids)
  counter = 1
  DispatchPlan.where(id: dp_ids).each do |dp|
    if dp.region == "North"
      dp.suggested_transporter_id = 384
      dp.suggested_transporter_name = "Fedex"
      dp.save
      shipment = dp.shipment
      if shipment.present?
        shipment.transporter_id = 384
        shipment.save(validate: false)
        if shipment.packaging_labels.present?
        shipment.packaging_labels.each do |pl|
          pl.delete
        end
        end
      end

      #CreateOrderToClickpostJob.perform_later(shipment.id)

      p "#{counter}. DP- #{dp.id}: Rerun: TRUE"
    elsif dp.region == "South"
      dp.suggested_transporter_id = 500
      dp.suggested_transporter_name = "Fedex South"
      dp.save
      shipment = dp.shipment
      if shipment.present?
      shipment.transporter_id = 500
      shipment.save(validate: false)
      if shipment.packaging_labels.present?
      shipment.packaging_labels.each do |pl|
        pl.delete
      end
      end
      end
      #CreateOrderToClickpostJob.perform_later(shipment.id)

      p "#{counter}. DP- #{dp.id}: Rerun: TRUE"
    else
      dp.suggested_transporter_id = 501
      dp.suggested_transporter_name = "Fedex West"
      dp.save
      shipment = dp.shipment
      if shipment.present?
      shipment.transporter_id = 501
      shipment.save(validate: false)
      if shipment.packaging_labels.present?
      shipment.packaging_labels.each do |pl|
        pl.delete
      end
      end
      end
      #CreateOrderToClickpostJob.perform_later(shipment.id)

      p "#{counter}. DP- #{dp.id}: Rerun: TRUE"
    end
    counter = counter + 1
  end
end
def rerun_clickpost(dispatch_plans)
  #dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  counter = 0
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    shipment = dispatch_plan.shipment
    counter += 1
    if shipment.present? && shipment.status == "ready_to_ship"
      if !shipment.packaging_labels.present?
        #result = CreateOrderToClickpostJob.perform_now(shipment.id)
        result = Logistics::Clickpost::CreateOrder.new({ shipment_id: shipment.id })
        response = result.create_order
        if response.meta.status == 200 || response.meta.status == 323
          update_shipment(response, shipment.id)
        end
        s = Shipment.find(shipment.id)
        #if result[:errors].present?
        # error = result[:errors]
        #end
        #p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{s.id}: Rerun: TRUE, Labels Generated- #{s.packaging_labels.present?} #{error}"
      else
        p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: FALSE, Labels Generated- #{shipment.packaging_labels.present?}"
      end
    elsif shipment.present? && shipment.status == "dispatched"
      p "#{counter}. ALREADY DISPATCHED: DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: FALSE, Labels Generated- #{shipment.packaging_labels.present?}"
    end
  end
end