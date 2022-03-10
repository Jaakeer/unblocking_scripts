#We can change this to have array as an input input = ([master_sku, difference], wh_id)
def adjust_all_stocks(master_sku, difference, wh_id)
  if difference > 0
    # all DPIRs for the SKU in the wh
    dpir = DispatchPlanItemRelation.filter(dispatch_plan_destination_address_id: Warehouse.find(wh_id).address.id, dispatch_mode: ["seller_to_warehouse", "warehouse_to_warehouse", "buyer_to_warehouse"], master_sku_id: master_sku, shipped_quantity: "shipped_quantity > 0").map {|dpir| dpir.id}
    dpir_list = [] #This will fill up if DPIR does not have any LI
    dpir_present = [] #This will fill up if DPIR has LI
    filled_location = []
    for dpir_id in dpir do
      if LotInformation.where(lot_infoable_id: dpir_id).blank?
        dpir_list.push(dpir_id)
      else
        dpir_present.push(dpir_id)
      end
    end

    location = Location.where(warehouse_id: wh_id).map(&:id) #all locations on the warehouse
    for dpirs_id in dpir_present do
      lot_infos = LotInformation.where(lot_infoable_id: dpirs_id).map(&:id)
      for lot_info_id in lot_infos do
        # This will be used to remove allocated locations from all location list that we declared above
        filled_location.push(LotInformationLocation.where(lot_information_id: lot_info_id).map(&:location_id)) #locations which are taken up by the SKU
      end
    end
    #Unique locations
    location = location - filled_location.flatten.uniq

    if dpir_list.blank?
      #When all DPIRs have LI under them
      p "There is no DPIR without Lot Information values, falling back to LIL check"
      create_lil(master_sku, difference, wh_id, location)
    else
      for d in dpir_list do
        lot_information = LotInformation.where(master_sku_id: master_sku, warehouse_id: wh_id, inward: true, is_valid: [true, nil])


        if DispatchPlanItemRelation.find(d).shipped_quantity >= difference
          #Creating LI alongwith LIL (This will throw and error even if locations used in past are empty)
          #REF: scope of is_valid in LIL model needs to include remaining_quantity: "remaining_quantity > 0"
          LotInformation.create!({
                                     lot_infoable_type: "DispatchPlanItemRelation",
                                     lot_infoable_id: d,
                                     lot_number: SecureRandom.uuid,
                                     quantity: difference,
                                     inward: true,
                                     master_sku_id: master_sku,
                                     warehouse_id: wh_id,
                                     is_valid: true,
                                     lot_information_locations_attributes: [{
                                                                                location_id: location.last,
                                                                                quantity: difference,
                                                                                status: 0,
                                                                                remaining_quantity: difference,
                                                                                is_valid: true
                                                                            }]
                                 })
          difference = 0
          WarehouseSkuStock.where(master_sku_id: master_sku, warehouse_id: wh_id).first.adjust
          break

        elsif DispatchPlanItemRelation.find(d).shipped_quantity < difference
          dpir_shipped_qty = DispatchPlanItemRelation.find(d).shipped_quantity

          LotInformation.create!({
                                     lot_infoable_type: "DispatchPlanItemRelation",
                                     lot_infoable_id: d,
                                     lot_number: SecureRandom.uuid,
                                     quantity: dpir_shipped_qty,
                                     inward: true,
                                     master_sku_id: master_sku,
                                     warehouse_id: wh_id,
                                     is_valid: true,
                                     lot_information_locations_attributes: [{
                                                                                location_id: location.last,
                                                                                quantity: dpir_shipped_qty,
                                                                                status: 0,
                                                                                remaining_quantity: dpir_shipped_qty,
                                                                                is_valid: true
                                                                            }]
                                 })
          location.delete(location.last)
          difference = difference - dpir_shipped_qty
        else
          #if no other DPIRs found to increase quantity
          p "No more DPIR to run through for #{master_sku}, falling back to LIL check with #{difference} quantity"
        end
      end
      #Once DPIR loop ends and difference is still positive it'll fallback to LIL check
      create_lil(master_sku, difference, wh_id, location)
    end

  else
    # Difference less than 0 ka case
    lot_info = LotInformation.where(master_sku_id: master_sku, warehouse_id: wh_id, inward: true, is_valid: [true, nil]).map(&:id)
    for l_id in lot_info do
      l = LotInformation.find(l_id)
      if l.lot_information_locations.present? && difference < 0
        for lil in l.lot_information_locations do
          if (-1 * lil.quantity) >= difference && LotInformation.where(lot_number: l.lot_number, inward: false, is_valid: [true, nil], master_sku_id: master_sku).blank? && difference < 0
            lil.quantity + difference
            lil.remaining_quantity + difference
            l.quantity + difference
            lil.save
            l.save
            difference = 0
            WarehouseSkuStock.where(master_sku_id: master_sku, warehouse_id: wh_id).first.adjust
            break
          elsif (-1 * lil.quantity) < difference && LotInformation.where(lot_number: l.lot_number, inward: false, is_valid: [true, nil], master_sku_id: master_sku).blank? && difference < 0
            lil.invalidate
            difference = lil.quantity + difference
          elsif difference == 0
              WarehouseSkuStock.where(master_sku_id: master_sku, warehouse_id: wh_id).first.adjust
              break
          else
              p "The lot numbers has been used in outwards or no more LIL could be found, please review #{master_sku} for #{difference}"
          end
        end
      elsif difference == 0
        WarehouseSkuStock.where(master_sku_id: master_sku, warehouse_id: wh_id).first.adjust
        break
      else
        p "No LIL entry found for #{master_sku}, please review"
      end
    end
  end

  p "Stocks adjusted for #{master_sku}" if difference == 0

  p "Stocks could not be adjusted for #{master_sku}, and pending to adjust is #{difference}, please review manually" if difference != 0

end


# This creates LIL if no LIL exist for LI
# This is tried and tested, I have reused this from my other collection
def update_lot_information(lot_location_and_code, total)
  for i in lot_location_and_code do
    lot_information_id = i[0]
    l_code = i[1]
    lot_info = LotInformation.find(lot_information_id)
    qty = total
    wh_id = lot_info.warehouse_id

    if lot_info.inward == true && (lot_info.is_valid == true or lot_info.is_valid == nil) && lot_info.quantity > 0
      lot_info.lot_information_locations.create(
          lot_information_id: lot_info.id,
          location_id: l_code,
          quantity: qty,
          status: :ok,
          remaining_quantity: qty,
          is_valid: true
      )
      p "\nLot information location is created successfully"
      WarehouseSkuStock.where(master_sku_id: lot_info.master_sku_id, warehouse_id: wh_id).first.adjust
      p "Stocks adjusted in the warehouse"
    else
      p lot_info
      p "\nLot information is invalid, please review"
    end
  end
end






# This will create LIL for missing ones
def create_lil(master_sku, difference, wh_id, location)
  lot_info = LotInformation.where(master_sku_id: master_sku, warehouse_id: wh_id, inward: true, is_valid: [true, nil]).map(&:id)
  for l_id in lot_info do
    l = LotInformation.find(l_id)
    break if difference == 0
    if l.lot_information_locations.blank? && l.quantity >= difference
      update_lot_information([[l.id, location.last]], difference)
      difference = 0
    elsif l.lot_information_locations.blank? && l.quantity < difference
      update_lot_information([[l.id, location.last]], l.quantity)
      difference = difference - l.quantity
      location.delete(location.last)
    end
  end

    #When all LI have LILs created/existing, fallback to updating the LILs
    difference = update_lil(master_sku, difference, wh_id) unless difference == 0

  return difference
end


# This will try to increase LIL quantity if LIL quantity is less than the LI quantity or increase in LI and LIL if LI quantity is less than DPIR.shipped_quantity
def update_lil(master_sku, difference, wh_id)
  lot_info = LotInformation.where(master_sku_id: master_sku, warehouse_id: wh_id, inward: true, is_valid: [true, nil]).map(&:id)
  for l_id in lot_info do
    l = LotInformation.find(l_id)

    #This will increase the quantity in LI and LIL if LI.quantity was already less than DPIR.shipped
    if l.quantity < l.dispatch_plan_item_relation.shipped_quantity && (l.dispatch_plan_item_relation.shipped_quantity - l.quantity) >= difference
      lot_info_location = l.valid_lot_information_locations.first if l.lot_information_locations.present?
      if lot_info_location.present?
        l.quantity = l.dispatch_plan_item_relation.shipped_quantity
        lot_info_location.remaining_quantity = lot_info_location.remaining_quantity + difference
        lot_info_location.quantity = lot_info_location + difference
        l.save
        lot_info_location.save
        difference = 0
        WarehouseSkuStock.where(master_sku_id: master_sku, warehouse_id: wh_id).first.adjust
        break
      else
        p "Could not update LIL since LIL is marked as invalid for #{l_id}, please review it separately if it shows up in final list SKU #{master_sku}"
      end

      #This will try to increase whatever quantity was missing in LI, if LI.qty is less than DPIR.shipped_qty but it still doesn't cover the difference
    elsif l.quantity < l.dispatch_plan_item_relation.shipped_quantity && (l.dispatch_plan_item_relation.shipped_quantity - l.quantity) < difference
      lot_info_location = l.valid_lot_information_locations.first if l.lot_information_locations.present?
      if lot_info_location.present?
      sum = (l.dispatch_plan_item_relation.shipped_quantity - l.quantity)
      l.quantity = l.quantity + sum
      lot_info_location.quantity = lot_info_location.quantity + sum
      lot_info_location.remaining_quantity = lot_info_location.remaining_quantity + sum
      l.save
      lot_info_location.save
      difference = difference - sum
      else
        p "Could not update LIL since LIL is marked as invalid for #{l_id}, please review it separately if it shows up in final list SKU #{master_sku}"
      end
    end
  end
  return difference
end