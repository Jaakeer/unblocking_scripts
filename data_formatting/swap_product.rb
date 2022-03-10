def fix_order_value(order_item_ids)
  order_item_ids.each do |order_item_id|
    order_item = OrderItem.find(order_item_id)
    next if order_item.blank?
    begin
      p "---------- Changing value for Order Item ID: #{order_item_id}, total amount: #{order_item.total_amount} ----------"

      order_item.placed_quantity = order_item.product_quantity
      p "1. Order Item placed_quantity changed to #{order_item.placed_quantity}"

      order_item.sold_at = order_item.placed_quantity * order_item.sku_value * order_item.price_per_unit
      order_item.seller_price = order_item.sold_at
      p "clickpost_sample.json. Order Item seller price changed to #{order_item.seller_price}"

      order_item.gst_amount = order_item.seller_price * (order_item.gst_percentage / 100)
      p "3. Order Item gst_amount has been changed to #{order_item.gst_amount}"
      p "Setting Total Seller Payable to 0"
      order_item.total_seller_payable = 0

      order_item.save!

      if order_item.total_amount != ((order_item.placed_quantity * order_item.sku_value * order_item.price_per_unit) + order_item.gst_amount + order_item.gst_on_ofc)
        change_order_amount(order_item)
      end

      p "Current total amount is #{order_item.total_amount}"
    rescue => e
      p "Something went wrong: #{e}"
    end
  end
end

def change_order_amount(order_item)
  order_item.total_amount = ((order_item.placed_quantity * order_item.sku_value * order_item.price_per_unit) + order_item.gst_amount + order_item.gst_on_ofc)
  order_item.save
end

