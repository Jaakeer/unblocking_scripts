
#input_data = (true, shipment_ids, true, true, [], true)
# context = {
#   crate_return: true / false,
#   shipment_ids: [shipment_ids],
#   take_inward: true / false,
#   create_outward_now: true / false,
#   outward_dp_ids: [outward_dp_ids],
#   mark_outward_delivered: true / false
# }
def execute_script(create_return, shipment_ids, take_inward, create_outward_now, outward_dp_ids, mark_outward_delivered)
  if create_return
    forward_shipment_ids = shipment_ids
    return_shipment_ids = create_return_shipment(forward_shipment_ids)
    final_return_shipment_ids = dispatch_return_shipments(return_shipment_ids)
  else
    final_return_shipment_ids = dispatch_return_shipments(shipment_ids)
  end

  if take_inward && final_return_shipment_ids.present?
  inward_output = take_inward_of_return_shipments(final_return_shipment_ids)
  li_ids = inward_output[0]
  processed_shipment_ids = inward_output[1]
  else
    li_ids = get_li_ids(shipment_ids)
    processed_shipment_ids = final_return_shipment_ids
  end

  if li_ids.present?
    if create_outward_now && outward_dp_ids.blank?
      outward_data = create_outward_dp(processed_shipment_ids)
      dp_ids = outward_data[0]
      failed_shipments = outward_data[1]
    else
      dp_ids = outward_dp_ids
    end

    outward_output = create_pick_list(dp_ids, li_ids)
    processed_dp_ids = outward_output[0].uniq
    failed_dpirs = outward_output[1]

    outward_shipment_ids = create_outward_shipment(processed_dp_ids)
    mark_shipment_delivered(outward_shipment_ids) if mark_outward_delivered
  else
    p "Couldn't inward as no LIs were found please review"
  end


  return final_return_shipment_ids, outward_shipment_ids, failed_dpirs, failed_shipments

end


def create_return_shipment(shipment_ids)
  shipments = Shipment.where(id: shipment_ids)
  error_shipment_ids = []
  return_shipment_ids = []
  i = 0

  shipments.each do |shipment|
    puts "Starting for shipment with id #{shipment.id}"
    #puts "-------------------------#{i} shipments have been marked as returned---------------------------------" if i%100 == 0
    next if shipment.return_shipments.present?
    dpir_params = []
      if activate_buyer_address(shipment)
        shipment.dispatch_plan_item_relations.each do |dpir|
          dpir_param = {
              order_item_id: dpir.order_item_id,
              quantity: dpir.quantity,
              shipped_quantity: dpir.shipped_quantity,
              quantity_unit: dpir.quantity_unit,
              expected_shipped_quantity: dpir.expected_shipped_quantity,
              pack_size: dpir.pack_size,
              length_in_cm: dpir.length_in_cm,
              breadth_in_cm: dpir.breadth_in_cm,
              height_in_cm: dpir.height_in_cm,
              dead_weight: dpir.dead_weight,
              volumetric_weight: dpir.volumetric_weight
          }

          dpir_params << dpir_param
        end

        timelines_params = [
            {
                timeline_type: "dispatch",
                deadline: Time.now,
                status: "open"
            },
            {
                timeline_type: "delivery",
                deadline: Time.now + 1.day,
                status: "open"
            }
        ]

        shipment_params = {
            no_of_packages: shipment.no_of_packages,
            forward_shipment_id: shipment.id,
            transporter_id: shipment.transporter_id,
            truck_size: shipment.truck_size,
            tracking_link: shipment.tracking_link,
            weight: shipment.weight,
            reason_for_return: "Issue in invoice",
            action_reason_id: 22
        }

        params = {
            dispatch_plan: {
                dispatch_mode: "buyer_to_warehouse",
                origin_address_id: shipment.dispatch_plan.destination_address_id,
                destination_address_id: 17350,
                transporter_type: "bizongo",
                admin_user_id: shipment.dispatch_plan.admin_user_id,
                owner_id: shipment.dispatch_plan.owner_id,
                dispatch_plan_item_relations_attributes: dpir_params,
                timelines_attributes: timelines_params,
                shipment_attributes: shipment_params
            }
        }

        begin
          create_service = DispatchPlanServices::Create.new(params)
          create_service.execute
          if create_service.errors.present?
            error_shipment_ids << shipment.id
            puts "Return shipment not created because of #{create_service.errors}"
          else
            return_shipment_ids.push(create_service.shipment_result[:shipment_id]) if create_service.shipment_result.present?
          end
        rescue => e
          error_shipment_ids << shipment.id
          puts "Return shipment not created because of #{e}"
        end

        i = i+1
      end
    end
  return return_shipment_ids
end

def activate_buyer_address(shipment)
  address_id = shipment.dispatch_plan.destination_address_id
  address = Address.find(address_id)
  if address.is_active
    return true
  else
    address.is_active = true
    if address.save!
      return true
    else
      return false
    end
  end
end

def dispatch_return_shipments(return_shipment_ids)
  shipments = Shipment.where(id: return_shipment_ids)
  error_shipment_ids = []
  error_dp_ids = []
  final_shipment_ids = []
  i = 0

  shipments.each do |shipment|
    puts "Starting for shipment with id #{shipment.id}"
    puts "-------------------------#{i} shipments have been marked as dispatched---------------------------------" if i%100 == 0
    if shipment.status == "dispatched" || shipment.status == "delivered"
      final_shipment_ids.push(shipment.id)
    else
      begin
        shipment.dispatched_at = Time.now
        shipment.status = "dispatched"
        unless shipment.save(validate: false)
          error_shipment_ids << shipment.id
          puts "Return shipment not dispatched because of #{shipment.errors.full_messages.join(', ')}"
        end

        dp = shipment.dispatch_plan
        dp.dispatch_timeline.update(completion_date: shipment.dispatched_at, status: 'done')

        dp.status = "done"
        if dp.save(validate: false)
          final_shipment_ids.push(shipment.id)
        else
          error_dp_ids << dp.id
          puts "Return dp not marked as done because of #{dp.errors.full_messages.join(', ')}"
        end
      rescue => e
        error_shipment_ids << shipment.id
        puts "Return shipment not dispatched because of #{e}"
      end
    end
    i = i+1
  end
  return final_shipment_ids
end

def take_inward_of_return_shipments(return_shipment_ids)
  shipments = Shipment.where(id: return_shipment_ids)
  error_shipment_ids = []
  li_ids = []
  final_shipment_ids = []

  shipments.each do |shipment|
    dpirs = shipment.dispatch_plan_item_relations
    warehouse_id = shipment.dispatch_plan.destination_address.try(:warehouse).try(:id)
    puts "-------------Starting for shipment with id #{shipment.id}-----------"
    address_id = check_transition_address(shipment.supplier_id)
    return_dp = shipment.dispatch_plan
    if return_dp.destination_address_id != address_id && address_id != 0
      return_dp.destination_address_id = address_id
      return_dp.save(validate: false)
      shipment.transition_address_id = address_id
      shipment.save(validate: false)
    end

    begin


        dpirs.each do |dpir|
          if dpir.lot_informations.where(inward: true).present?
            li_ids.push(dpir.lot_informations.where(inward: true).map(&:id))
          else
          location = Location.where(warehouse_id: shipment.transition_address.warehouse.id, code: "VRTL").first #For Oyo we created a location named TESTOYO in each warehouse
          location = Location.create({ warehouse_id: shipment.transition_address.warehouse.id, code: "VRTL" }) if location.blank?
          li_params = {
              lot_number: SecureRandom.uuid,
              quantity: dpir.shipped_quantity,
              inward: true,
              is_valid: true,
              lot_infoable_id: dpir.id,
              lot_infoable_type: "DispatchPlanItemRelation",
              warehouse_id: shipment.transition_address.warehouse.id,
              master_sku_id: dpir.master_sku_id,
              lot_information_locations_attributes: [
                  {
                      quantity: dpir.shipped_quantity,
                      remaining_quantity: dpir.shipped_quantity,
                      is_valid: true,
                      status: "ok",
                      location_id: location.id
                  }
              ]
          }

          li = LotInformation.new()
          li.assign_attributes(li_params)

          if li.save(validate: false)
            li_ids.push(li.id)
          else
            puts "LI not created for shipment with id #{shipment.id} because of #{li.errors.full_messages.join(', ')}"
            error_shipment_ids << shipment.id

          end
          end
        end

        if shipment.dispatched?
          shipment.status = "delivered"
          shipment.delivered_at = Time.now

          if shipment.save(validate: false)
            final_shipment_ids.push(shipment.id)
            dp = shipment.dispatch_plan
            dp.status = "done"
            dp.save(validate: false)
          else
            puts "Shipment not marked as delivered for shipment with id #{shipment.id} because of #{shipment.errors.full_messages.join(', ')}"
            error_shipment_ids << shipment.id
          end

        end
    rescue => e
      error_shipment_ids << shipment.id
      puts "Return shipment not delivered and LIs not created because of #{e}"
    end
  end
  return li_ids.flatten.uniq, final_shipment_ids
end

def get_li_ids(shipment_ids)
  dpir_ids = []
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    dpir_ids << shipment.dispatch_plan_item_relations.map(&:id)
  end
  dpir_ids = dpir_ids.flatten

  li_ids = []
  dpirs = DispatchPlanItemRelation.where(id: dpir_ids)
  dpirs.each do |dpir|
    li_ids.push(dpir.lot_informations.map(&:id))
  end

  return li_ids.flatten
end

def check_transition_address(supplier_id)
  address_id = 0
  case supplier_id
  when 9508
    address_id = 15343
  when 7746
    address_id = 16192
  when 9816
    address_id = 17718
  when 4606
    address_id = 17350
  when 14388
    address_id = 17718
  else
    address_id
  end
  return address_id
end



# output = [inward_dp, outward_dp, outward_shipment, invoice]
def create_outward_dp(return_shipment_ids)
  outward_dp_ids = []
  failed_shipments = []
  return_shipment_ids.each do |return_shipment_id|
    return_shipment = Shipment.find(return_shipment_id)
    return_dp = return_shipment.dispatch_plan
    return_dp_id = return_dp.id

    address_id = check_transition_address(return_shipment.supplier_id)
    if return_dp.destination_address_id != address_id && address_id != 0
      return_dp.destination_address_id = address_id
      return_dp.save(validate: false)
      return_shipment.transition_address_id = address_id
      return_shipment.save(validate: false)
    end

    @dispatch_plan_params = create_dp_context(return_dp_id)[:dispatch_plan]

    begin
      @dispatch_plan = DispatchPlan.create(@dispatch_plan_params)
      if @dispatch_plan.errors.present?
        p "#{@dispatch_plan.errors.full_messages}"
        failed_shipments.push(return_shipment_id)
      else
        @result = @dispatch_plan
        outward_dp_ids.push(@result.id)
      end
    rescue => e
      p "Failed because #{e}"
      failed_shipments.push(return_shipment_id)
    end

  end
  return outward_dp_ids, failed_shipments
end

def create_dp_context(return_dp_id)
  return_dp = DispatchPlan.find(return_dp_id)
  return_shipment_id = return_dp.shipment.id
  dpir_params = item_relations_attributes(return_dp)
    ref_shipment = return_dp.shipment
    ref_shipment.status = "delivered"
    return_dp.status = "done"
    if ref_shipment.save(validate: false) && return_dp.save(validate: false)
      request_context =  {
          dispatch_plan: {
              dispatch_mode: "warehouse_to_buyer",
              description: "",
              origin_address_id: return_dp.destination_address_id,
              destination_address_id: return_dp.origin_address_id,
              status: "open",
              admin_user_id: return_dp.admin_user_id,
              owner_id: return_dp.owner_id,
              transporter_type: "bizongo",
              transporter_name: "",
              no_of_days_to_deliver: 0,
              dispatch_plan_item_relations_attributes: dpir_params,
              timelines_attributes: [
                  {
                      timeline_type: 'dispatch',
                      deadline: DateTime.now + 1,
                      status: 'open'
                  },
                  {
                      timeline_type: 'delivery',
                      deadline: DateTime.now + 2,
                      status: 'open'
                  }
              ]
          }
      }
    end

  return request_context
end

def item_relations_attributes(dp)
  group_item_relations = []
  dp.dispatch_plan_item_relations.each do |dpir|
    item_relation = {
        order_item_id: dpir.order_item_id,
        quantity: dpir.quantity,
        quantity_unit: dpir.quantity_unit,
        master_sku_id: dpir.master_sku_id,
        product_details: dpir.product_details
    }
    group_item_relations.push(item_relation)
  end
  return group_item_relations
end

def invalidate(li_ids)
  lis = LotInformation.where(id: li_ids)
  lis.each do |li|
    li.invalidate
    p "LotInformation: #{li.id} is invalidated"
    li.adjust_warehouse_sku_stocks
  end
end

def revalidate_li(li_ids)
  final_li_ids = []
  i = 1
  li_ids.each do |li_id|
    li = LotInformation.find(li_id)
    li.lot_information_locations.each do |lil|
      p "#{lil.id} is being revalidated"
      lil.is_valid = true
      lil.remaining_quantity = lil.quantity

      unless lil.save(validate: false)
        puts "LIL not validated for lil id #{lil.id} because of #{lil.errors.full_messages.join(', ')}"
      end
    end

    li.is_valid = true
    if li.save(validate: false)
      final_li_ids.push(li.id)
      p "#{i}. LotInformation: #{li_id} has been validated"
    else
      puts "LI not validated for li id #{li.id} because of #{li.errors.full_messages.join(', ')}"
    end
    i = i+1
  end
  return final_li_ids
end

def create_pick_list(dp_ids, li_ids)


  dispatch_plans = DispatchPlan.where(id: dp_ids)

  lils = LotInformationLocation.where(lot_information_id: li_ids)
  # We will be using li_ids we got in script number 4.
  lis = LotInformation.where(id: li_ids)

  dispatch_plan_item_relations = DispatchPlanItemRelation.where(dispatch_plan_id: dp_ids)

  dpir_and_dp_for_no_location = []
  dpir_id_with_errors = []
  processed_dpirs = []

  begin
    dispatch_plan_item_relations.each do |dpir|
      puts "-----------------------------------Starting to create picklist for DPIR with id #{dpir.id}-----------------------------------"
      master_sku_id = dpir.master_sku_id
      warehouse_id = dpir.dispatch_plan.try(:origin_address).try(:warehouse).try(:id)
      sku = MasterSku.find(master_sku_id)

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

            if li.save(validate: false)
              processed_dpirs.push(dpir.dispatch_plan_id)
            else
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

            if li.save(validate: false)
              processed_dpirs.push(dpir.dispatch_plan_id)
            else
              puts "LI not created for dpir with id #{dpir.id} because of #{li.errors.full_messages.join(', ')}"
              dpir_id_with_errors.push(dpir.id, master_sku_id: master_sku_id)
            end

            required_quantity = required_quantity - lot_information_location.remaining_quantity
          end
        end
      else
        dpir_and_dp_for_no_location << {dpir_id: dpir.id, master_sku_id: master_sku_id}
      end
    end
  rescue => e
    puts "LI not created for dp with id because of #{e}"
  end
  return processed_dpirs, dpir_id_with_errors
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

def create_outward_shipment(dp_ids)

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
      puts "Starting for dispatch plan with id #{dp.id}"
      if dp.shipment.present?
        shipment_ids.push(dp.shipment.id)
      else

      dpir_params = []

      dp.dispatch_plan_item_relations.each do |dpir|
        dpir_param = {
            id: dpir.id,
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
        shipment = create_service.result
        shipment_ids.push([shipment.id, shipment.buyer_invoice_no])
      end
      end

    end
  rescue => e
    puts "--------------------------------------------------------SHIPMENT AND INVOICE CREATION FAILED BECAUSE OF #{e}--------------------------------------------------------"
  end
  return shipment_ids
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
