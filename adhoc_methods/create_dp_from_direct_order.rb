def push_accepted_order_items_for_auto_creation(direct_order_id)
  direct_order = DirectOrder.find(direct_order_id)
  context = SupplyDispatcher::Communicator.auto_create_checkpoint(create_auto_dispatch_plan_creation_request(direct_order))
  return context
end

def create_auto_dispatch_plan_creation_request(direct_order)
  order_items_request = []
  direct_order.order_items.each do |order_item|
    order_items_request << {
      order_item_id: order_item.id,
      delivery_date: direct_order.delivery_date,
      quantity: order_item.product_quantity * order_item.sku_value,
      selling_in_units: order_item.selling_in_units,
      master_sku_id: order_item.child_product.product.master_sku.id,
      child_product_id: order_item.child_product.id,
      sku_type: order_item.child_product.product.master_sku.sku_type,
      destination_address_id: order_item.direct_order.actual_shipping_address.id,
      admin_user_id: order_item.admin_user_id,
      owner_id: order_item.owner_id
    }
  end

  {
    order_items: order_items_request,
    delivery_date: direct_order.delivery_date,
    billing_entity_id: direct_order.order_items.first.child_product.company_id
  }
end
