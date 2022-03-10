def check_product_details(dispatch_plan_ids)
  product_details = Hash.new
  dispatch_plan_ids.each do |dispatch_plan_id|

    DispatchPlanItemRelation.where(dispatch_plan_id: dispatch_plan_id).each do |dpir|
      master_sku_id = dpir.master_sku_id
      order_item_id = dpir.master_sku_id
      product_details[order_item_id] = { master_sku_id: master_sku_id }
      response = Hashie::Mash.new Bizongo::Communicator.order_items_index!({ ids: [order_item_id] })
      order_items = response[:order_items]
      order_items.each do |order_item|
        vol_weight = order_item.sku_volumetric_weight
        dead_weight = order_item.dead_weight
      end
    end
  end
end
