def execute_now(dp_ids, li_ids, data)
  create_pick_list(dp_ids, li_ids)
  create_outward_shipment(dp_ids, data)
  mark_shipment_delivered(dp_ids)
end

def create_pick_list(dp_ids, li_ids)
  lils = LotInformationLocation.where(lot_information_id: li_ids)
  # We will be using li_ids we got in script number 4.
  lis = LotInformation.where(id: li_ids)
  dpir_and_dp_for_no_location = []
  dpir_id_with_errors = []
  dp_for_no_location = []
  dispatch_plans = DispatchPlan.where(id: dp_ids)
  dispatch_plans.each do |dispatch_plan|
    if dispatch_plan.origin_address_id != 16192
    dispatch_plan.origin_address_id = 16192
    dispatch_plan.save(validate: false)
    end
  begin
    dispatch_plan.dispatch_plan_item_relations.each do |dpir|
      puts "-----------------------------------Starting to create picklist for DPIR with id #{dpir.id}-----------------------------------"
      master_sku_id = dpir.master_sku_id
      p "MASTER SKU: #{master_sku_id}"
      warehouse_id = dpir.dispatch_plan.try(:origin_address).try(:warehouse).try(:id)
      sku = MasterSku.find(master_sku_id)
      p "WAREHOUSE ID: #{warehouse_id}"
      required_quantity = dpir.quantity

      lot_information_locations = lils.remaining_quantity.for_warehouse_sku(warehouse_id, sku.id).valid_records

      if lot_information_locations.present?
        lot_information_locations.each do |lot_information_location|
          available = lot_information_location.remaining_quantity - required_quantity

          if available >= 0
            lot_information = lot_information_location.lot_information
            location_attributes = [lot_information_location_attributes(lot_information_location.location_id, required_quantity)]

            params = lot_information_attributes(dpir.id, lot_information.lot_number, required_quantity, location_attributes, master_sku_id, warehouse_id, false)

            li = LotInformation.new()
            li.assign_attributes(params)

            unless li.save(validate: false)
              puts "LI not created for dpir with id #{dpir.id} because of #{li.errors.full_messages.join(', ')}"
              dpir_id_with_errors << {dpir_id: dpir.id, master_sku_id: master_sku_id}
            end

            break
          else
            lot_information = lot_information_location.lot_information
            location_attributes = [lot_information_location_attributes(lot_information_location.location_id, lot_information_location.remaining_quantity)]

            params = lot_information_attributes(dpir.id, lot_information.lot_number, lot_information_location.remaining_quantity, location_attributes, master_sku_id, warehouse_id, false)

            li = LotInformation.new()
            li.assign_attributes(params)

            unless li.save(validate: false)
              puts "LI not created for dpir with id #{dpir.id} because of #{li.errors.full_messages.join(', ')}"
              dpir_id_with_errors << {dpir_id: dpir.id, master_sku_id: master_sku_id}
            end

            required_quantity = required_quantity - lot_information_location.remaining_quantity
          end
        end
      else
        dpir_and_dp_for_no_location << {dpir_id: dpir.id, dp_id: dpir.dispatch_plan_id, master_sku_id: master_sku_id}
      end
    end
  rescue => e
    puts "LI not created for dp with id because of #{e}"
  end
  end
  return dpir_id_with_errors, dpir_and_dp_for_no_location
end

def lot_information_attributes(dpir_id, lot_number, quantity, location_attributes, sku_id, warehouse_id, inward)
  {
      lot_infoable_type: "DispatchPlanItemRelation",
      lot_infoable_id: dpir_id,
      lot_number: lot_number,
      quantity: quantity,
      inward: inward,
      master_sku_id: sku_id,
      warehouse_id: warehouse_id,
      is_valid: true,
      lot_information_locations_attributes: location_attributes
  }
end

def lot_information_location_attributes(location_id, quantity)
  {
      location_id: location_id,
      quantity: quantity,
      status: :ok,
      remaining_quantity: 0,
      is_valid: true
  }
end

def create_outward_shipment(dp_ids, data)

  dispatch_plans = DispatchPlan.where(id: dp_ids)

  # Did this activity to make sure that the DPs don't have any suggested transporter, else a request will be sent to clickpost after shipment creation.
  dispatch_plans.each do |dp|
    dp.suggested_transporter_name = nil
    dp.suggested_transporter_id = nil
    dp.pick_list_status = "ok"
    dp.save(validate: false)
  end

  error_dp_ids = []
  shipment_ids = []

  begin
    dispatch_plans.each do |dp|
      if dp.shipment.present?
        UpdateDpPriceJob.perform_now([dp.id], true)
      else


      puts "Starting for dispatch plan with id #{dp.id}"

      dpir_params = []

      dp.dispatch_plan_item_relations.each do |dpir|
        oi = dpir.order_item_id
        if dpir.child_product_id.blank?
          data.each do |d|
            oi_id = d[0]
            child_id = d[1]
            if oi == oi_id
              dpir.child_product_id = child_id
              dpir.save
            end
          end
        end

        dpir_param = {
            id: dpir.id,
            child_product_id: dpir.child_product_id,
            order_item_id: dpir.order_item_id,
            shipped_quantity: dpir.quantity,
            expected_shipped_quantity: dpir.quantity,
            master_sku_id: dpir.master_sku_id
        }

        dpir_params << dpir_param
      end

      dp_param = {
          id: dp.id,
          dispatch_plan_item_relations_attributes: dpir_params
      }

      shipment_attributes = {
          dispatch_plan_id: dp.id,
          no_of_packages: 1,
          transporter_id: 95,
          tracking_id: "NA",
          truck_size: dp.truck_type,
          status: "ready_to_ship",
          weight: 12,
          tracking_link: "NA",
          create_invoice: true
      }

      shipment_create_params = {
          dispatch_plan: dp_param,
          shipment_attributes: shipment_attributes
      }

      create_service = ShipmentServices::Create.new(shipment_create_params)
      create_service.execute

      if create_service.errors.present?
        error_dp_ids << dp.id
        puts "Shipment and invoice not created for dp with id #{dp.id} because of #{create_service.errors}"
      else
        shipment_ids << create_service.result.id
      end

      end
    end
  rescue => e
    puts "--------------------------------------------------------SHIPMENT AND INVOICE CREATION FAILED BECAUSE OF #{e}--------------------------------------------------------"
  end
end

def mark_shipment_delivered(ids)
  shipments = Shipment.where(dispatch_plan_id: ids)

  shipments.each do |s|
    puts "Starting for shipment with id #{s.id}"
    next if s.delivered?
    if s.ready_to_ship?
      s.dispatched_at = s.created_at
      s.delivered_at = s.created_at
      s.status = "delivered"
      if s.save!(validate: false)
        p "Shipment #{s.id} marked as delivered"
      end

      dp = s.dispatch_plan
      dp.dispatch_timeline.update(completion_date: s.dispatched_at, status: 'done')
      dp.delivered_timeline.update(completion_date: s.delivered_at, status: 'done')

      dp.status = "done"
      dp.save!(validate: false)
    elsif s.dispatched?
      s.delivered_at = s.dispatched_at
      s.status = "delivered"
      if s.save!(validate: false)
        p "Shipment #{s.id} marked as delivered"
      end

      dp = s.dispatch_plan
      dp.delivered_timeline.update(completion_date: s.delivered_at, status: 'done')
    end
  end
end

lils = LotInformationLocation.where(lot_information_id: li_ids)

lils.map(&:remaining_quantity)
total_remaining_quantity = lils.map(&:remaining_quantity).sum()


dpirs = DispatchPlanItemRelation.where(dispatch_plan_id: dp_ids)
non_li_dpirs = []

dpirs.each do |dpir|
  non_li_dpirs << dpir.id if dpir.lot_informations.blank?
end

