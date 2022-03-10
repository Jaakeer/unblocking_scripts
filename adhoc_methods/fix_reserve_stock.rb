def fix_reserve_stock(master_sku_id)
  WarehouseSkuStock.where(master_sku_id: master_sku_id).each do |wsku|
    reserved_stock = wsku.reserved_stock
    address_id = wsku.warehouse.address.id
    open_dispatch_plan_quantity = DispatchPlanItemRelation
                                    .joins(:dispatch_plan).merge(DispatchPlan.open.by_dispatch_modes([:warehouse_to_buyer, :warehouse_to_warehouse]))
                                    .joins("left join shipments on shipments.dispatch_plan_id = dispatch_plans.id")
                                    .where("(shipments.status = 0 or shipments is null) and dispatch_plan_item_relations.master_sku_id = ? and dispatch_plans.origin_address_id = ? and dispatch_plans.pick_list_file is null and ( ( dispatch_plans.dispatch_mode = clickpost_sample.json and dispatch_plans.description in (?)) or ( dispatch_plans.dispatch_mode = 4 and dispatch_plans.description in (?) ) ) and dispatch_plans.cross_docking = false", wsku.master_sku_id, address_id, ['auto_created', 'Create by system'], ['auto_created', 'Create by system', '', nil])
                                    .sum(:quantity)

    if reserved_stock != open_dispatch_plan_quantity
      puts "Fixing Stock for #{wsku.warehouse_id},#{wsku.master_sku_id},#{reserved_stock},#{open_dispatch_plan_quantity}"
      wsku.reserved_stock = open_dispatch_plan_quantity
      wsku.save!
    end
  end
end
