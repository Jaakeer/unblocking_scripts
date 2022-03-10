def inward_outward(original_dp, outward_dp_id)
  inward_dp_id = initiate_return(original_dp)
  inward_dp = DispatchPlan.find(inward_dp_id)
  inward_shipment = inward_dp.shipment
  outward_dp = DispatchPlan.find(outward_dp_id)
  begin
    success = create_lot_information(inward_shipment.id, "shipment")
  rescue => e
    p "something went wrong, please review #{e}"
  end

  if success
    begin
      inward_shipment.status = "Delivered"
      if(inward_shipment.save(validate: false))
        outward_shipment = create_outward_shipment(outward_dp)
      end

    rescue => e
    p "Outward shipment couldn't be created #{e}"
    end

  end

  if outward_shipment != 0
    outward_shipment.status = "delivered"
    outward_shipment.save(validate: false)
  else
    p "Outward shipment could not be created"
  end
end

def create_outward_shipment(outward_dp)
  outward_shipment = 0
  shipment_params = shipment_create_params(outward_dp)
  begin
    success = create_lot_information(outward_dp.id, "dp")
    if success
      begin
        create_service = ShipmentServices::Create.new(remove_empty_params(shipment_params))
        create_service.execute!
      rescue => e
        next
      end
    end

  rescue => e
    p "something went wrong, please review"
  end
  outward_shipment = outward_dp.shipment if present?
  outward_shipment
end

def shipment_create_params(dispatch_plan)
  #Need to change the params to pull from existing data
  shipment_params = {
      dispatch_plan: [
          :id,
          dispatch_plan_item_relations_attributes:[
              :id,
              :order_item_id,
              :bizongo_po_item_id,
              :child_product_id,
              :shipped_quantity,
              :expected_shipped_quantity,
              :pack_size,
              :master_sku_id,
              locations:[:quantity,:location_id,:location_code,:inward_lot_info_id,condition:[:key,:value],location:[:location_id,:location_code]],
              lot_informations_attributes: [:lot_number,:quantity,:inward,:master_sku_id,:warehouse_id,lot_information_locations_attributes: [:location_id,:quantity,:status]],
              lot_informations: [:master_sku_id,lot_information_locations: [:location_code,:location_id,:quantity,:status]]
          ]
      ],
      shipment_attributes: [
          :dispatch_plan_id,
          :no_of_packages,
          :seller_invoice_no,
          :transporter_id,
          :tracking_id,
          :weight,
          :tracking_link,
          :delivered_at,
          :dispatched_at,
          :truck_size,
          :reason_for_wrong_suggested_truck,
          :buyer_invoice_no,
          :buyer_delivery_challan_no,
          :status,
          :account_type,
          :seller_invoice_date,
          :seller_invoice_file,
          :seller_pod_file,
          :coa_document,
          :transporter_name,
          :service_type,
          :driver_name,
          :driver_number,
          :eway_bill,
          :estimated_shipping_charges,
          :truck_number,
          :create_invoice,
          :actual_charges,
          :inward,
          shipment_documents_attributes: [:attachment_id, :document_type, :document_number]
      ]}

  return shipment_params
end

def create_lot_information(input, input_type)
  success = false
  if input_type == "shipment"
    dp = Shipment.find(input).dispatch_plan
    inward = true
    warehouse_id = Address.find(dp.destination_address_id).warehouse.id
  elsif input_type == "dp"
    dp = DispatchPlan.find(input)
    inward = false
    warehouse_id = Address.find(dp.origin_address_id).warehouse.id
  else
    p "Input not valid"
    break
  end

  begin
  if dp.present?
    if Location.where(code: "VRTL", warehouse_id: warehouse_id).present?
      location_id = Location.where(code: "VRTL", warehouse_id: warehouse_id).first.id
    else
      new_location = Location.create(code: "VRTL", warehouse_id: warehouse_id)
      location_id = new_location.id
    end

    dp.dispatch_plan_item_relations.each do |dpir|

      if inward
        remaining_qty = dpir.quantity
        lot_number = SecureRandom.uuid
      else
        inward_li = Lotinformation.joins(:lot_information_locations).where("lot_informations.master_sku_id = ? and lot_informations.warehouse_id = ? and lot_informations.inward = ? and lot_informations.quantity = ? and lot_information_locations.remaining_quantity = ? and lot_information_locations.location_id", dpir.master_sku_id, warehouse_id, true, dpir.quantity, dpir.quantity, location_id).first
        remaining_qty = 0
        lot_number = inward_li.lot_number
      end

      LotInformation.create({
                                lot_infoable_type: "DispatchPlanItemRelation",
                                lot_infoable_id: dpir.id,
                                lot_number: lot_number,
                                quantity: dpir.quantity,
                                inward: inward,
                                master_sku_id: dpir.master_sku_id,
                                warehouse_id: warehouse_id,
                                is_valid: true,
                                lot_information_locations_attributes: [{
                                                                           location_id: location_id,
                                                                           quantity: dpir.quantity,
                                                                           status: :ok,
                                                                           remaining_quantity: remaining_qty,
                                                                           is_valid: true
                                                                       }]
                            })

      if dpir.lot_informations.present?
        lil = inward_li.lot_information_locations.first
        lil.remaining_quantity = 0
        lil.save
        WarehouseSkuStock.where(master_sku_id: inward_li.master_sku_id, warehouse_id: inward_li.warehouse_id).first.adjust
        success = true
      end

    end
  end
  rescue => e
    success = false
    p "Something went wrong while creating lot information"
  end
  success
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