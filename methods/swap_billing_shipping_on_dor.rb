def fix_address(direct_order_id)
    for id in direct_order_id do
        direct_order = DirectOrder.find(id)

        billing_address_id = direct_order.direct_order_shipping_address.shipping_address_id
        shipping_address_id = direct_order.direct_order_billing_address.billing_address_id

        ship_add = direct_order.direct_order_shipping_address
        bill_add = direct_order.direct_order_billing_address

        ship_add.shipping_address_id = shipping_address_id
        ship_add.save!

        bill_add.billing_address_id = billing_address_id
        bill_add.save!

        direct_order.snap_me

        order_item_id = (direct_order.order_items.first.id)
        final.push([order_item_id, shipping_address_id])
    end

    return final
end