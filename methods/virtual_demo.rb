#shipments = [133978, 133977, 133976, 133975, 133974, 133973, 133972, 133971, 133970, 133969, 133968, 133967, 133966, 133965, 133964, 133963, 133962, 133961, 133960, 133959, 133958, 133957, 133956, 133955, 133954, 133953, 133952, 133951, 133950, 133949, 133948, 133947, 133946, 133945, 133944, 133943, 133942, 133941, 133940, 133939, 133938, 133937, 133936, 133935, 133934, 133932, 133931, 133929, 133928, 133927, 133926, 133925, 133924, 133923, 133586, 133589, 133922, 133921, 133920, 133919, 133918, 133917, 133916, 133592, 133591, 133590, 133588, 133587, 133585, 133584, 133583, 133582, 133581, 133580, 133579, 133578, 133577, 133576, 133575, 133574, 133572, 133571, 133570, 133569, 133568, 133566, 133565, 133564, 133563, 133562, 133561, 133559, 133558, 133557, 133556, 133555, 133554, 133553, 133551, 133550, 133549, 133548, 133546, 133545, 133544, 133543, 133542, 133541, 133540, 133539, 133538, 133537]

def take_inward_of_return_shipments(shipments)
  #SCRIPT TO DELIVER THE RETURN SHIPMENT
  return_shipment_ids = shipments
  shipments = Shipment.where(id: return_shipment_ids)
  error_shipment_ids = []

  shipments.each do |shipment|
    dpirs = shipment.dispatch_plan_item_relations
    warehouse_id = shipment.dispatch_plan.destination_address.try(:warehouse).try(:id)
    puts "-------------Starting for shipment with id #{shipment.id}-----------"

    begin
      ActiveRecord::Base.transaction do

        dpirs.each do |dpir|
          next if dpir.lot_informations.where(inward: true).present?
          location = Location.where(warehouse_id: shipment.transition_address.warehouse.id, code: "VRTL_DIGI_AGE").first #For Oyo we created a location named TESTOYO in each warehouse
          location = Location.create({ warehouse_id: shipment.transition_address.warehouse.id, code: "VRTL_DIGI_AGE" }) if location.blank?
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

          unless shipment.save(validate: false)
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
end

def swap_child_id(invoices)
  order_item_ids = []
  dp_ids = []
  new_child_product_id = 52592
  invoices.each do |invoice_no|
    shipment = Shipment.where(buyer_invoice_no: invoice_no).first
    dpir = shipment.dispatch_plan_item_relations.where(master_sku_id: 14393).first
    unless dpir.blank?
      dpir.child_product_id = new_child_product_id
      order_item_ids.push(dpir.order_item_id) if dpir.save
      dp_id = shipment.dispatch_plan_id
      dp_ids.push(dp_id)
    end
  end
  [order_item_ids, dp_ids.uniq]
end

def swap_oi_child_id(order_item_ids)
  new_child_product_id = 52592
  result = Hash.new
  order_item_ids.each do |oi_id|
    oi = OrderItem.find(oi_id)
    child_product_id = oi.child_product_id
    oi.child_product_id = new_child_product_id
    oi.gst_percentage = 12.0
    oi.gst_service_percentage = 12.0
    if oi.save
      po_item = oi.direct_order.purchase_order.purchase_order_items.where(child_product_id: child_product_id).first
      unless po_item.blank?
        po_item.child_product_id = new_child_product_id
        po_item.gst_percentage = 12.0
        result[oi.id] = po_item.save
      end
    end
  end
  result
end

#order_item_ids = [order_item_id1, order_item_id2, ....]
def regenerate(order_item_ids)
  final_dp_list = []
  order_item_ids.each do |oi_id|
    dp_ids = DispatchPlanItemRelation.where(order_item_id: oi_id).map(&:dispatch_plan_id)
    final_dp_list.push(dp_ids)
  end
  final_dp_list = final_dp_list.flatten.uniq
  regenerate_invoices(final_dp_list)
end
def regenerate_invoices(dp_ids)
  UpdateDpPriceJob.perform_now(dp_ids, true)
end
