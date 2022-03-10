`mark_returned_dispatched (true/false),
take_inward (true/false),
create_outward_dp_now(true/false),
[return_shipment_ids],
[forward_dp_ids] put value if you ran it on bizongo backend and got all the created dp_ids,
or if you want to create now pass an empty array []`

# input_data = [boolean, boolean, boolean, array, array]
# example: shipment_ids = [shipment1, shipment2, ..]
# input_data = [false, true, false, shipment_ids, []]

def execute(input_data)
  mark_return_dispatched = input_data[0]
  take_inward = input_data[1]
  create_dp_now = input_data[2]
  return_shipment_ids = input_data[3]
  final_shipment_ids = []

  if mark_return_dispatched
    returned_shipment_ids = dispatch_return_shipments(return_shipment_ids)
  else
    returned_shipment_ids = return_shipment_ids
  end

  if take_inward
    li_ids = take_inward_of_return_shipments(returned_shipment_ids)
  else
    li_ids = get_li_ids(returned_shipment_ids)
  end

  if create_dp_now
    forward_dp_ids = create_outward_dp(returned_shipment_ids)
  else
    forward_dp_ids = input_data[4]
  end
  if forward_dp_ids.present? && li_ids.present?
    final_dp_ids = create_pick_list(forward_dp_ids, li_ids)
    if final_dp_ids.present?
      final_shipment_ids = create_outward_shipment(final_dp_ids)
    else
      p "final_dp IDs missing for forward"
    end
  else
    p "No Forward DP found while creating picklist"
  end

  remaining_quantity = check_virtual_stock(li_ids)
  if remaining_quantity > 0
    p "***************** PLEASE REVIEW STOCKS: #{remaining_quantity} is still in the virtual location ***************"
  end
  return final_shipment_ids
end

def dispatch_return_shipments(return_shipment_ids)
  #SCRIPT TO DISPATCH THE RETURN SHIPMENTS
  shipments = Shipment.where(id: return_shipment_ids)
  error_shipment_ids = []
  error_dp_ids = []
  shipment_ids = []
  i = 0

  shipments.each do |shipment|
    puts "Starting for shipment with id #{shipment.id}"

    begin
      shipment.dispatched_at = Time.now
      shipment.status = "dispatched"
      if shipment.save(validate: false)
        shipment_ids.push(shipment.id)
      else
        error_shipment_ids << shipment.id
        puts "Return shipment not dispatched because of #{shipment.errors.full_messages.join(', ')}"
      end

      dp = shipment.dispatch_plan
      dp.dispatch_timeline.update(completion_date: shipment.dispatched_at, status: 'done')

      dp.status = "done"
      unless dp.save(validate: false)
        error_dp_ids << dp.id
        puts "Return dp not marked as done because of #{dp.errors.full_messages.join(', ')}"
      end
    rescue => e
      error_shipment_ids << shipment.id
      puts "Return shipment not dispatched because of #{e}"
    end
    i = i+1
  end
  return shipment_ids
end

def take_inward_of_return_shipments(return_shipment_ids)
  #SCRIPT TO DELIVER THE RETURN SHIPMENT
  shipments = Shipment.where(id: return_shipment_ids)
  error_shipment_ids = []
  li_ids = []
  shipments.each do |shipment|
    dpirs = shipment.dispatch_plan_item_relations
    warehouse_id = shipment.dispatch_plan.destination_address.try(:warehouse).try(:id)
    puts "Shipment Id:  #{shipment.id}"

    begin
      ActiveRecord::Base.transaction do

        dpirs.each do |dpir|
          next if dpir.lot_informations.where(inward: true).present?
          location = Location.where(warehouse_id: shipment.transition_address.warehouse.id, code: "VRTL").first
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

          unless li.save(validate: false)
            puts "LI not created for shipment with id #{shipment.id} because of #{li.errors.full_messages.join(', ')}"
            error_shipment_ids << shipment.id
            raise ActiveRecord::Rollback
          end
        end

        if shipment.dispatched?
          shipment.status = "delivered"
          shipment.delivered_at = Time.now

          if shipment.save(validate: false)
            CreateBizongoCreditNoteJob.perform_now(shipment.id)
            dpir_ids = shipment.dispatch_plan_item_relations.map(&:id)
          dpir_ids = dpir_ids.flatten
          dpirs = DispatchPlanItemRelation.where(id: dpir_ids)
          dpirs.each do |dpir|
            li_ids << dpir.lot_informations.map(&:id)
          end
          li_ids = li_ids.flatten
          else
            puts "Shipment not marked as delivered for shipment with id #{shipment.id} because of #{shipment.errors.full_messages.join(', ')}"
            error_shipment_ids << shipment.id
            raise ActiveRecord::Rollback
          end

          shipment.dispatch_plan.delivered_timeline.update(completion_date: shipment.delivered_at, status: 'done')
        end
      end
    rescue => e
      error_shipment_ids << shipment.id
      puts "Return shipment not delivered and LIs not created because of #{e}"
    end
  end
  invalidate_li(li_ids)
  return li_ids
end

def get_li_ids(shipments)
  dpir_ids = []
  shipments.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    dpir_ids << shipment.dispatch_plan_item_relations.map(&:id)
  end
  dpir_ids = dpir_ids.flatten

  li_ids = []
  dpirs = DispatchPlanItemRelation.where(id: dpir_ids)
  dpirs.each do |dpir|
    li_ids << dpir.lot_informations.map(&:id)
  end
  return li_ids.flatten
end

def invalidate_li(li_ids)
  lis = LotInformation.where(id: li_ids)
  lis.each do |li|
    li.invalidate
    li.adjust_warehouse_sku_stocks
  end
end

def revalidate_li(li_ids)
  lis = LotInformation.where(id: li_ids)
  lis.each do |li|
    li.lot_information_locations.each do |lil|
      lil.is_valid = true

      unless lil.save(validate: false)
        puts "LIL not validated for lil id #{lil.id} because of #{lil.errors.full_messages.join(', ')}"
      end
    end

    li.is_valid = true
    unless li.save(validate: false)
      puts "LI not validated for li id #{li.id} because of #{li.errors.full_messages.join(', ')}"
    end
  end
end

`def check_stock(shipment_ids)
  li_data = get_li_data(shipment)
  lils = LotInformationLocation.where(lot_information_id: li_data)

  lils.map(&:remaining_quantity)
  total_remaining_quantity = lils.map(&:remaining_quantity).sum()
  return total_remaining_quantity
end
`

def create_pick_list(dp_ids, li_ids)
  lils = LotInformationLocation.where(lot_information_id: li_ids)
  # We will be using li_ids we got in script number 4.
  dispatch_plan_item_relations = DispatchPlanItemRelation.where(dispatch_plan_id: dp_ids)

  dpir_and_dp_for_no_location = []
  dpir_id_with_errors = []
  final_dp_ids = []
  dp_for_no_location = []

  begin
    #revalidate_li(li_ids)
    dispatch_plan_item_relations.each do |dpir|
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
        final_dp_ids.push(dpir.dispatch_plan_id)
      else
        dpir_and_dp_for_no_location << {dpir_id: dpir.id, master_sku_id: master_sku_id}
      end
    end
  rescue => e
    puts "LI not created for dp with id because of #{e}"
  end
  return final_dp_ids
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
        shipment_id = create_service.result.id
        buyer_invoice = Shipment.find(shipment_id).buyer_invoice_no
        shipment_ids.push([dp.id, shipment_id, buyer_invoice])
      end

    end
  rescue => e
    puts "SHIPMENT AND INVOICE CREATION FAILED BECAUSE OF #{e}"
  end
  return shipment_ids
end

def mark_shipment_delivered(shipment_id)
  result = false
  s = Shipment.where(id: shipment_id).first
  puts "Starting for shipment with id #{s.id}"
    if s.delivered?
      result = true
    elsif s.ready_to_ship?
        s.dispatched_at = s.created_at
        s.delivered_at = s.created_at
        s.status = "delivered"
        s.save!(validate: false)

        dp = s.dispatch_plan
        dp.dispatch_timeline.update(completion_date: s.dispatched_at, status: 'done')
        dp.delivered_timeline.update(completion_date: s.delivered_at, status: 'done')

        dp.status = "done"
        result = dp.save!(validate: false)
    elsif s.dispatched?
        s.delivered_at = s.dispatched_at
        s.status = "delivered"
        result = s.save!(validate: false)

        dp = s.dispatch_plan
        dp.delivered_timeline.update(completion_date: s.delivered_at, status: 'done')
    end

  return result
end

def create_dp_context(return_dp_id)
  return_dp = DispatchPlan.find(return_dp_id)
  return_shipment_id = return_dp.shipment.id
  dpir_params = item_relations_attributes(return_dp)

  if(mark_shipment_delivered(return_shipment_id))
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
  else
    p "Return could not be marked as delivered"
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

def create_outward_dp(return_shipment_ids)
  dispatch_plans = []
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
      else
        @result = @dispatch_plan
        dispatch_plans.push(@result.id)
      end
    rescue => e
      p "Failed because #{e}"
    end

  end
  return dispatch_plans
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

def check_virtual_stock(li_ids)

  lils = LotInformationLocation.where(lot_information_id: li_ids)
  lils.map(&:remaining_quantity)
  total_remaining_quantity = lils.map(&:remaining_quantity).sum()

  return total_remaining_quantity
end