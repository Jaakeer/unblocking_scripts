def close_dors(direct_order_ids)
  failed_to_close = []
  direct_order_ids.each do |direct_order_id|
    direct_order = DirectOrder.find(direct_order_id)
    next if direct_order.status == "completed" || direct_order.status == "cancelled"
    rollback_order_item = get_all_planned_dispatches(direct_order)
    rolled_back = rollback_orders(rollback_order_item) if rollback_order_item.present?
    unless rolled_back
      failed_to_close.push(direct_order_id)
    end
  end

  close_po(direct_order_ids)
  failed_to_close
end

def get_all_planned_dispatches(direct_order)
  rollback_order_item = Hash.new
  direct_order.order_items.each do |oi|
    rollback_order_item[oi.id] = oi.product_quantity * oi.sku_value.to_i
  end

  response = SupplyDispatcher::Communicator.dispatch_plan_relation_index!(order_item_ids: [direct_order.order_items.pluck(&:id)], dispatch_plan_status: [:open, :done])
  dpirs = Hashie::Mash.new(response).dispatch_plans
  if dpirs.present?
    dpirs.each do |dpir|
      p "-------------------------Starting with DPIR ID: #{dpir.id}-------------------------"
      if dpir.dispatch_mode == "seller_to_buyer" || dpir.dispatch_mode == "seller_to_warehouse"
        p "Order Item #{dpir.order_item_id} has some S-B or S-W DPs, #{dpir.quantity} won't be rolled_back"

      elsif dpir.picklist_generated.nil?
        p "-------------------------Calculating Shipped (#{dpir.shipped_quantity}) and Returned Quantity (#{dpir.returned_quantity})-------------------------"
        rollback_order_item[dpir.order_item_id] -= dpir.shipped_quantity
        rollback_order_item[dpir.order_item_id] += dpir.returned_quantity
      end
    end
  else
    p "-------------------------No DPIRs found, Cancelling the DOR #{direct_order.id}-------------------------"
    direct_order.cancelled!
  end
  return rollback_order_item
end

def rollback_orders(rollback_order_item)
  rolled_back = false
  rollback_order_item.each do |order_item_id,rollback_quantity|
    order_item_id = order_item_id.to_i
    order_item = OrderItem.find(order_item_id)
    rollback_quantity = rollback_quantity
    begin
      if update_order_item(order_item, rollback_quantity)
        rolled_back = update_delivery_request(order_item, rollback_quantity)
      else
        p "Order Item couldn't be rolled back ID: #{order_item.id}, Qty: #{order_item.product_quantity * order_item.sku_value.to_i}, Rollback qty: #{rollback_quantity}"
      end
    rescue => e
      p "ERROR: #{e}"
      rolled_back = false
    end

  end
  rolled_back
end

def update_order_item(order_item, rollback_quantity)
  sku_value = order_item.sku_value.to_i
  if order_item.product_quantity * sku_value == rollback_quantity
    p "--------------------You are trying to make order item quantity 0. Cancelling the order item (#{order_item.id}) instead--------------------"
    order_item.delivery_status = "cancelled"
    return order_item.save!
  elsif order_item.product_quantity * sku_value < rollback_quantity
    return false
  else
    order_item.product_quantity -= (rollback_quantity/sku_value)
    order_item.placed_quantity -= (rollback_quantity/sku_value)
    return order_item.save!
  end
end

def update_delivery_request(order_item, rollback_quantity)
  delivery_request_item = get_delivery_request_item(order_item)
  if delivery_request_item.present? && delivery_request_item.quantity > rollback_quantity
    delivery_request_item.quantity -= rollback_quantity
    return delivery_request_item.save!
  elsif delivery_request_item.quantity == rollback_quantity
    p "-------The delivered quantity is 0 for #{delivery_request_item.id}, deleting entry-------"
    return delivery_request_item.delete
  elsif delivery_request_item.quantity < rollback_quantity
    p "Roll back quantity is greater than the delivery item quantity"
  else
    p "Can't find Delivery Request for #{order_item.id}"
    return false
  end
end

def get_delivery_request_item(order_item)
  delivery_request_item = nil
  order_item.direct_order.delivery_group.delivery_requests.each do |dr|
    if dr.actual_shipping_address.street_address == order_item.direct_order.shipping_address.street_address
      dr.delivery_request_items.each do |dri|
        if dri.child_product_id == order_item.child_product_id
          delivery_request_item = dri
          break
        end
      end
    end
  end
  delivery_request_item
end

def close_po(direct_order_ids)
  po_ids = get_po_ids(direct_order_ids)
  po_ids.each do |po_id|
    po = PurchaseOrder.find(po_id)
    next if po.status == "closed"
    po.status = "closed"
    po.closure_reason = "ageing_of_the_po"
    po.save
  end
end

def get_po_ids(direct_order_ids)
  direct_orders = DirectOrder.where(id: direct_order_ids)
  po_ids = direct_orders.map(&:purchase_order_id)
  return po_ids.uniq
end

def find_all_order_items(direct_order_ids)
  order_item_ids = OrderItem.where(direct_order_id: direct_order_ids).map(&:id).flatten.uniq
  order_item_ids
end

def close_all_dors(direct_order_ids)
  non_cancelled_dors = Hash.new
  adjusted_dors = Hash.new
  direct_order_ids.each do |dor_id|
    dor = DirectOrder.find(dor_id)
    next if dor.status == "cancelled"
    begin
      dor.status = "pending"
      dor.save(validate: false)

      service = DirectOrderServices::CancelDirectOrder.new dor_id
      service.execute
      if service.errors.present?
        p "DOR couldn't be cancelled or closed due to #{service.errors}"
        non_cancelled_dors[dor_id] = service.errors
      else
        adjusted_dors[dor_id] = "DOR successfully processed"
      end
    rescue => e
      p "------------------Error while fetching data: #{e}-----------------"
      non_cancelled_dors[dor_id] = e
    end
  end
  [non_cancelled_dors, adjusted_dors]
end