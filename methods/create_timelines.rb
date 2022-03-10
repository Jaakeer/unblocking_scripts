def create_timelines(purchase_orders)
    purchase_orders.each do |po_no|

    po_id = BizongoPurchaseOrder.where(po_number: po_no).first.id
    dispatch_plans = DispatchPlan.where(bizongo_purchase_order_id: po_id).map(&:id)

        dispatch_plans.each do |dp_id|
            dp = DispatchPlan.find(dp_id)

                dispatch_date = DateTime.now
                    dp.timelines.each do |dispatch|
                    dispatch.deadline = dispatch_date
                    dispatch.save(validate: false)
                end
                f_date = dispatch_date - 1.day

                timeline_types = [0,1,3]

                timeline_types.each do |type|

                    if dp.timelines.where(timeline_type: type).blank?

                        timelines_create_params= {
                            timeline: {
                                timeline_type: type,
                                dispatch_plan_id: dp.id,
                                deadline: dispatch_date,
                                status: "open",
                                follow_up_date: f_date,
                                original_deadline: dispatch_date,
                                created_at: dispatch_date,
                                updated_at: dispatch_date
                                }
                        }
                        service = TimelineServices::Create.new(timelines_create_params)
                        service.execute!
                    end
                end
        end
    end
end




po.each do |po_no|
    pos = BizongoPurchaseOrder.where(po_number: po_no).first
    pos.status = "accepted"
    pos.save(validate: false)
    end




po.bizongo_po_items.each do |poi|
    child_id = poi.child_product_id
    new_child_id = ChildProduct.find(child_id).product.child_products.where(company_id: 4606).first.id
    poi.child_product_id = new_child_id
    poi.save
end


def create_timelines(purchase_orders)
    purchase_orders.each do |po_no|

    po_id = BizongoPurchaseOrder.where(po_number: po_no).first.id
    dispatch_plans = DispatchPlan.where(bizongo_purchase_order_id: po_id).map(&:id)

        dispatch_plans.each do |dp_id|
            dp = DispatchPlan.find(dp_id)
            timeline = dp.timelines.where(timeline_type: 3).first
            timeline.status = "open"
            timeline.follow_up_date = DateTime.yesterday
            timeline.save(validate: false)
        end
    end
end
