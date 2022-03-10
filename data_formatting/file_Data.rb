  def volumetric_weight_and_dead_weight_for_order_item(dp_id, data)
    @dispatch_plan = DispatchPlan.find(dp_id)
    @item_details = @dispatch_plan.dispatch_plan_item_details
    data.each do |ref|
        order_item_id = ref[0]
        quantity = ref[1]
      order_item = @item_details[:order_items].find { |order_item| order_item[:id] == order_item_id }
      if order_item.present?
        pack_size = order_item.product_matrix.value
        no_of_packages = (quantity.to_f / pack_size.to_f).to_f

        vol_and_dead_weight = {
            vol_weight: (order_item.sku_volumetric_weight.to_f * no_of_packages).to_f,
            dead_weight: (order_item.sku_dead_weight.to_f * no_of_packages).to_f
        }
        return vol_and_dead_weight
      end
    end
  end


  def dispatch_plan_item_details
    start_time = Time.now
    @bizongo_po_items = []
    @order_items = []
    @child_products = []
    if PO_ITEM_DISPATCH_MODE.include?(self.dispatch_mode.to_sym)
      bizongo_po_item_ids = self.dispatch_plan_item_relations.pluck(:bizongo_po_item_id)
      if bizongo_po_item_ids.compact.present?
        response = Hashie::Mash.new Bizongo::Communicator.bizongo_po_items_index!({ids: bizongo_po_item_ids})
        @bizongo_po_items = response[:bizongo_po_items]
      end
    end
    if ORDER_ITEM_DISPATCH_MODE.include?(self.dispatch_mode.to_sym)
      order_item_ids = self.dispatch_plan_item_relations.pluck(:order_item_id)
      if order_item_ids.compact.present?
        response = Hashie::Mash.new Bizongo::Communicator.order_items_index!({ids: order_item_ids})
        @order_items = response[:order_items]
      end
    end
    if self.warehouse_to_warehouse?
      child_product_ids = self.dispatch_plan_item_relations.pluck(:child_product_id)
      if child_product_ids.compact.present?
        response = Hashie::Mash.new Bizongo::Communicator.child_products_index!({ids: child_product_ids})
        @child_products = response[:child_products]
      end
    end
    end_time = Time.now

    Rails.logger.info "Execution time for method DispatchPlan::dispatch_plan_item_details - #{(end_time - start_time) * 1000} ms"
    {order_items: @order_items, bizongo_po_items: @bizongo_po_items, child_products: @child_products}
  end