def fix_reserve_stock(master_sku)
    for i in master_sku do
        actual = 0
        whouse_id = []
        dispatch_plan_item_relation = DispatchPlanItemRelation.filter(dispatch_mode: "warehouse_to_buyer", dispatch_plan_status: "open", master_sku_id: i, dispatch_plan_description: ["created_by_system", "auto_created"]).map {|p| p}
        if dispatch_plan_item_relation.blank?
            whouse = WarehouseSkuStock.where(master_sku_id: i).map(&:id)
            for wh_id in whouse do
                wh = WarehouseSkuStock.find(wh_id)
                if wh.reserved_stock != 0
                    wh.reserved_stock = 0
                    wh.save
                else
                    next
                end
            end
        else
            for d in dispatch_plan_item_relation do
                actual = actual + d.quantity
                warehouse_address = d.dispatch_plan.origin_address_id
                whouse_id.push(Address.find(warehouse_address).warehouse.id) if Address.find(warehouse_address).warehouse.present?
            end
            whouse_id = whouse_id.uniq

            for w in whouse_id do
            if WarehouseSkuStock.where(warehouse_id: w, master_sku_id: i).present? && WarehouseSkuStock.where(warehouse_id: w, master_sku_id: i).first.reserved_stock != 0
                serial = WarehouseSkuStock.where(warehouse_id: w, master_sku_id: i).first.id
                WarehouseSkuStock.update(id: serial, warehouse_id: whouse_id, master_sku_id: i, reserved_stock: actual)
            else
                next
            end
        end
    end
    end
end
master_skus = MasterSku.all.map {|x| x.id}