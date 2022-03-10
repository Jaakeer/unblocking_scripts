def check_open_pos
  po_items = []
  DirectOrder.where("created_at > '1 Jan, 2020*'").cancelled.each do |direct_order|
    direct_order.order_items.each do |order_item|
      bizongo_po_items = BizongoPoItem.where(order_item_id: order_item.id)
      bizongo_po_items.each do |bizongo_po_item|
        bizongo_po_item.order_item_id = nil
        if bizongo_po_item.save
          po_items.push(bizongo_po_item.id)
        end
      end
    end
  end
  po_items
end
