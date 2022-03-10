# frozen_string_literal: true

# [dp_id, master_sku_id, qty, location]
def create_lot_information(refs)
  counter = 1
  refs.each do |ref|
    dp_id = ref[0]
    master_sku_id = ref[1]
    qty = ref[2]
    location = ref[3]
    dp = DispatchPlan.find(dp_id)
    shipment = dp.shipment
    warehouse_id = dp.destination_address.addressable_id
    location_id = Location.where(code: location, warehouse_id: warehouse_id).first.id
    dpir = dp.dispatch_plan_item_relations.where(master_sku_id: master_sku_id).first
    p "#{counter}. Creating lot information for SKU: #{master_sku_id}, Qty: #{qty}, DPIR: #{dpir.id}, Location: #{location}"
    next if dpir.lot_informations.present? || shipment.nil?

    begin
      lot_number = LotInformation.generate_lot_number_by_master_sku_id_and_date(master_sku_id, DateTime.now)
      LotInformation.create({
                              lot_infoable_type: 'DispatchPlanItemRelation',
                              lot_infoable_id: dpir.id,
                              lot_number: lot_number,
                              quantity: qty,
                              inward: true,
                              master_sku_id: master_sku_id,
                              warehouse_id: warehouse_id,
                              is_valid: true,
                              lot_information_locations_attributes: [{
                                location_id: location_id,
                                quantity: qty,
                                status: 'ok',
                                remaining_quantity: qty,
                                is_valid: true
                              }]
                            })
      p 'SUCCESS: Stock info successfully created'
      unless shipment.status == 'delivered'
        shipment.status = 'delivered'
        shipment.delivered_at = DateTime.now
        shipment.save!
        p "Shipment #{shipment.id} has been marked as delivered"
      end
    rescue StandardError => e
      p "ERROR: Something went wrong: #{e}"
    end
    counter += 1
  end
end

LotInformation.create({
                        lot_infoable_type: 'DispatchPlanItemRelation',
                        lot_infoable_id: dpir.id,
                        lot_number: SecureRandom.uuid,
                        quantity: dpir.shipped_quantity,
                        inward: true,
                        master_sku_id: dpir.master_sku_id,
                        warehouse_id: 15,
                        is_valid: true,
                        lot_information_locations_attributes: [{
                          location_id: Location.where(code: location,
                                                      warehouse_id: 15).first.id,
                          quantity: dpir.shipped_quantity,
                          status: :ok,
                          remaining_quantity: dpir.shipped_quantity,
                          is_valid: true
                        }]
                      })
# #Update Lot Information Location
# [52115, "R6C2CL"]
def update_lot_information(lot_location_and_code)
  lot_location_and_code.each do |i|
    lot_information_id = i[0]
    l_code = i[1]
    lot_info = LotInformation.find(lot_information_id)
    qty = lot_info.quantity
    w_id = lot_info.warehouse_id

    loc_id = Location.where(code: l_code, warehouse_id: w_id).first.id

    if lot_info.inward == true && ((lot_info.is_valid == true) || lot_info.is_valid.nil?) && lot_info.quantity.positive?
      lot_info.lot_information_locations.create(
        lot_information_id: lot_info.id,
        location_id: loc_id,
        quantity: qty,
        status: :ok,
        remaining_quantity: qty,
        is_valid: true
      )
      puts "\nLot information location is created successfully"
      WarehouseSkuStock.where(master_sku_id: lot_info.master_sku_id, warehouse_id: lot_info.warehouse_id).first.adjust
      puts 'Stocks adjusted in the warehouse'
    else
      puts lot_info
      puts "\nLot information is invalid, please review"
    end
  end
end

def adjust_stocks(sku, warehouse)
  warehouse.each do |w_id|
    loc = LotInformation.where(master_sku_id: sku, warehouse_id: w_id, inward: true, is_valid: [true, nil]).map(&:id)
    loc.each do |i|
      if LotInformation.find(i).lot_information_locations.present?
        sum = LotInformationLocation.where(lot_information_id: i).map(&:quantity).sum
        change = LotInformationLocation.where(lot_information_id: i).first
        if LotInformation.find(i).quantity != sum
          change.quantity = change.quantity + (LotInformation.find(i).quantity - sum)
          change.remaining_quantity = change.remaining_quantity + (LotInformation.find(i).quantity - sum)
          change.save!
        else
          next
        end
      else
        next
      end
    end
  end
end

def create_lot_info(dispatch_plan_ids)
  counter = 1
  DispatchPlan.where(id: dispatch_plan_ids).each do |dispatch_plan|
    p "#{counter}. Starting with DP: #{dispatch_plan.id}"
    dispatch_plan.dispatch_plan_item_relations.each do |dpir|
      next if dpir.lot_informations.exists?

      p "....DPIR: #{dpir.id}, SKU: #{dpir.master_sku_id}"
      warehouse_id = dispatch_plan.destination_address_snapshot['addressable_id']
      location_id = Location.where(code: 'Floor001', warehouse_id: warehouse_id).first.id
      quantity = dpir.shipped_quantity
      begin
        lot_number = LotInformation.generate_lot_number_by_master_sku_id_and_date(dpir.master_sku_id, DateTime.now)
        LotInformation.create({
                                lot_infoable_type: 'DispatchPlanItemRelation',
                                lot_infoable_id: dpir.id,
                                lot_number: lot_number,
                                quantity: quantity,
                                inward: true,
                                master_sku_id: dpir.master_sku_id,
                                warehouse_id: warehouse_id,
                                is_valid: true,
                                lot_information_locations_attributes: [{
                                  location_id: location_id,
                                  quantity: quantity,
                                  status: :ok,
                                  remaining_quantity: quantity,
                                  is_valid: true
                                }]
                              })
        p '....SUCCESS: Stock info successfully created'
      rescue StandardError => e
        p "....ERROR: Something went wrong: #{e}"
      end
    end
    counter += 1
  end.nil?
end

def create_lot_informations(_dispatch_plan_id, master_sku)
  warehouse_id = @manual_inward_params[:warehouse_id]
  locations = @manual_inward_params[:location_quantity]
  lot_number = if @manual_inward_params[:lot_number].present?
                 @manual_inward_params[:lot_number]
               else
                 LotInformation.generate_lot_number_by_master_sku_id_and_date(
                   master_sku, DateTime.now
                 )
               end
  location_attributes = []
  sku_locations = {}
  sku_locations[master_sku] = []
  quantity = 0
  locations.each do |location|
    unless location[:location_id].present?
      error "Please select location from list for sku #{master_sku} copy paste will not work "
    end
    return unless valid?

    if sku_locations[master_sku].include?(location[:location_id])
      error "Multiple locations cannot be used for same SKU #{master_sku}"
    end
    return unless valid?

    sku_locations[master_sku] << location[:location_id]
    quantity += location[:quantity].to_i
    location_attributes << lot_information_location_attributes(location[:location_id], location[:quantity])
  end
  li = LotInformation.create(lot_information_attributes(manual_inward_id, lot_number, quantity, location_attributes,
                                                        master_sku, warehouse_id))
  error li.errors.full_messages if li.errors.present?
  return unless valid?
end
