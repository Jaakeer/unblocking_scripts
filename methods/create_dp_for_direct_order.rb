def create_dp_for_direct_order(direct_order_id)
  direct_order = DirectOrder.find_by_id(direct_order_id)
  result = push_accepted_order_items_for_auto_creation(direct_order)
  if result.blank?
    p "Job ran, but result is blank"
  else
    p "Job ran successfully: #{result}"
  end
end


def push_accepted_order_items_for_auto_creation(direct_order)
  context = create_auto_dispatch_plan_creation_request(direct_order)
  result = SupplyDispatcher::Communicator.auto_create_checkpoint(context)
  result
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
