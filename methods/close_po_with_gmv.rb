def close_po(purchase_orders)
    final = []
    for i in purchase_orders do
    po = PurchaseOrder.find(i)

    dor = po.direct_orders.map {|d| d.id}
    for j in dor do
        dor_oi = j.order_items.map {|oi| [oi.id, oi.placed_quantity]}
        final.push([j.id, dor_oi])
    end
return final
end




def close_po_validate(final)
    for i in final do






def regenerate_invoice(invoices)
    dispatch_plan = []
    for i in invoices do
        UpdateDpPriceJob.perform_now(Shipment.where(buyer_invoice_no: i).map {|d| d.dispatch_plan_id}, true)
    end
end




def create_order_item_returned_qty_map(shipments)
  order_item_returned_qty_map = Hash.new
  shipments.each do |shipment|
    shipment.dispatch_plan_item_relations.each do |dispatch_plan_item_relation|
      if order_item_returned_qty_map[dispatch_plan_item_relation.order_item_id].blank?
        order_item_returned_qty_map[dispatch_plan_item_relation.order_item_id] = 0
      end
      order_item_returned_qty_map[dispatch_plan_item_relation.order_item_id] += dispatch_plan_item_relation.quantity
    end
  end
  return order_item_returned_qty_map
end
def create_po_child_product_map(purchase_order_items)
  poi_child_product_map = Hash.new
  purchase_order_items.each do |purchase_order_item|
    poi_child_product_map[purchase_order_item.child_product_id] = purchase_order_item
  end
  return poi_child_product_map
end
def short_close_dors (po_id_list)
  purchase_order_items = PurchaseOrderItem.get_by_purchase_order(po_id_list)
  poi_child_product_map = create_po_child_product_map(purchase_order_items)
  order_item_returned_qty_map = {}
  dor_ids = []
  po_id_list.each do |po|
    dor_ids = PurchaseOrder.find(po).direct_orders.pluck('id')
    response = SupplyDispatcher::Communicator.shipment_index!(direct_order_ids:dor_ids, shipment_status:[:returned])
    shipments = Hashie::Mash.new(response).shipments
    if shipments.present?
      order_item_returned_qty_map = create_order_item_returned_qty_map(shipments)
    end
  end
  order_items = OrderItem.get_by_direct_order(dor_ids)
  if order_items.present?
    order_items.each do |order_item|
      poi_child_product_map[order_item.child_product_id].open_quantity = poi_child_product_map[order_item.child_product_id].total_quantity - (order_item.delivered_quantity - order_item_returned_qty_map[order_item.id])
      poi_child_product_map[order_item.child_product_id].save!
    end
  end
end