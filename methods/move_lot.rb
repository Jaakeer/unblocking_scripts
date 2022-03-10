def move_lot_information(dp_old, dp_new)
    dispatch_plan_old = DispatchPlan.find(dp_old)
    dispatch_plan_new = DispatchPlan.find(dp_new)

    dispatch_plan_old.dispatch_plan_item_relations.each do |dpir_new|
        dispatch_plan_new.dispatch_plan_item_relations.each do |dpir_old|
            if dpir_old.master_sku_id == dpir_new.master_sku_id
                p "Swapping DPIR for #{dpir_old.master_sku_id}"
                    begin
                        dpir_old.lot_informations.each do |li|
                            li.lot_infoable_id = dpir_new.id
                            li.save
                            p "#{li.id} is now using #{dpir_new.id} as lot_infoable_id"
                    rescue => e
                    end
                end
            end
        end
    end
end

def validate_lot_informations(dispatch_plans)
    dispatch_plans.each do |dp_id|
        DispatchPlan.find(dp_id).dispatch_plan_item_relations.each do |dpir|
        if dpir.lot_informations.present?
            dpir.lot_informations.each do |li|
                li.is_active = true
                li.save
                li.lot_information_locations.each do |lil|
                    lil.is_valid = true
                    lil.save
                end
            end
        else
            p "No Lot Information for DPIR: #{dpir.id}"
        end
        end
    end
end