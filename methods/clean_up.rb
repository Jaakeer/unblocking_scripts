#input >> order_items = [order_item_id1, order_item_id2, order_item_id3, ...]
def adjust_order_items(order_items)
    orders_to_cancel = []
    adjusted_orders = []
    order_items.each do |order_item_id|
        order_item = OrderItem.find(order_item_id)
        actual_order_quantity = 0
        sum = 0
        reference = "cancel"
        direct_order = order_item.direct_order

        #get dispatch plan details from supply chain
        response = SupplyDispatcher::Communicator.dispatch_plan_relation_index!(order_item_ids: [order_item_id], dispatch_plan_status: [:open, :done] )
        dispatch_plan_item_relations = Hashie::Mash.new(response).dispatch_plans

        if dispatch_plan_item_relations.present?
            p "#{sum}"
            actual_order_quantity += dispatch_plan_item_relations.sum(&:quantity)
            p "#{actual_order_quantity}"
            if dispatch_plan_item_relations.map(&:returned_quantity).present?
                dispatch_plan_item_relations.map(&:returned_quantity).each do |qty|
                    if qty == nil
                        next
                    else
                        sum = sum + qty.to_i
                    end
                end
               actual_order_quantity = actual_order_quantity - sum
            end
            if (order_item.product_quantity*order_item.sku_value).to_i > actual_order_quantity
                p "#{(order_item.product_quantity*order_item.sku_value)}"
                difference = (order_item.placed_quantity*order_item.sku_value.to_i - actual_order_quantity)
                p "Here the difference is #{difference}"
                begin
                adjust_order_values(order_item, difference)
                p "Order Item #{order_item_id} adjusted, new product_quantity is #{OrderItem.find(order_item_id).product_quantity*OrderItem.find(order_item_id).sku_value}"
                po_item = adjusted_orders.push([order_item_id, "adjusted"])
                rescue => e
                 p "Something went wrong with #{order_item_id}"
                end
            elsif (order_item.product_quantity*order_item.sku_value.to_i) < actual_order_quantity
                p "Order Item #{order_item_id} has lesser quantity than dispatch_plans' quantity"
            else
                p "Order Item #{order_item_id} is perfectly balanced, like all things should be"
            end
        else
            if direct_order.order_items.count == 1
                direct_order.status = "cancelled"
                direct_order.save(validate: false)
            else
                orders_to_cancel([order_item_id, order_item.placed_quantity*order_item.sku_value])
                p "Multiple Order Items in the DOR, please review #{direct_order.id}"
            end
        end
    end
    return [orders_to_cancel, adjusted_orders]
end



def adjust_order_values(order_item, difference)
    quantity = (difference.to_i/order_item.sku_value.to_i)
    po_item = order_item.direct_order.delivery_group.purchase_order_items.where(child_product_id: order_item.child_product_id).first
    if po_item.present?
        p "#{difference} is difference"
            begin
            order_item.product_quantity -= quantity
            order_item.save!
            order_item.placed_quantity = order_item.product_quantity
            order_item.save!
            rescue => e
             p "Order item has some issues please review"
            end
            po_item.open_quantity += difference.to_i
            po_item.save
    else
        p "PO Item could not be found"
    end
end


'''#orders_to_cancel = [[order_item_id1, actual_order_quantity, reference], [...], ..]
#run these in bizongo backend with reference_data collected from above method
def adjust_order_items(orders_to_cancel)
    po_adjustments = []
    po_item_adjustment = 0
    difference = 0
    orders_to_cancel.each do |reference_data|
        order_item_id = reference_data[0]
        actual_order_quantity = reference_data[1]
        reference = reference_data[clickpost_sample.json]
        order_item = OrderItem.find(order_item_id)
        direct_order = order_item.direct_order
        if order_item.placed_quantity > actual_order_quantity
            if reference == "dp_exist"
                if actual_order_quantity > 0
                    difference = order_item.product_quantity - actual_order_quantity
                    order_item.product_quantity = actual_order_quantity
                    order_item.save(validate: false)
                    po_adjustments.push([order_item_id, direct_order.id, difference, "difference"])
                else
                    po_adjustments.push([order_item_id, direct_order.id, 0, "no_difference"])
                end

            elsif reference == "cancel"
                if OrderItem.where(direct_order_id: direct_order.id).count == 1
                    direct_order.status = "cancelled"
                    direct_order.save(validate: false)
                else
                    po_adjustments.push([order_item_id, direct_order.id, order_item.placed_quantity, "difference"])
                end
            else
                po_adjustments.push([order_item_id, direct_order.id, 0, reference])
            end
        end
    end

    adjust_po_items(po_adjustments)
end'''




