adjustments_made = []
'''
=begin

def calculate_delivery_date_from_dispatch_date(dp)
    origin_address = dp.origin_address

    destination_address = dp.destination_address

    delivery_date = DeliveryDay.calculate_delivery_date_from_dispatch_date(
        origin_address.city,
        origin_address.pincode,
        destination_address.city,
        destination_address.pincode,
        dispatch_date
    )
    delivery_date
end


  def delivery_date(dp)
    delivery_date = calculate_delivery_date_from_dispatch_date(dp)
    delivery_date[:delivery_date]
  end

  def dispatch_date
    DateTime.tomorrow
  end



  def create_item_relation_context(dispatch_item_relation, adjustment)
    item_relations = {}
      item_relations = {
        bizongo_po_item_id: dispatch_item_relation.bizongo_po_item_id,
        child_product_id: dispatch_item_relation.child_product_id,
        quantity: adjustment,
        quantity_unit: dispatch_item_relation.quantity_unit,
        production_plan_id: dispatch_item_relation.production_plan_id
      }
    {dispatch_item_relation: item_relations}
  end


def create_dispatch_plan_context(dp, dpir, adjustment)
    delivery = delivery_date(dp)
    p "#{delivery}"
    dp_content = {}
    dp_content =  {
            dispatch_plan: {
                dispatch_mode: dp.dispatch_mode,
                description: "",
                origin_address_id: dp.origin_address_id,
                destination_address_id: dp.destination_address_id,
                status: dp.status,
                admin_user_id: dp.admin_user_id,
                owner_id: dp.owner_id,
                transporter_type: dp.transporter_type,
                transporter_name: dp.transporter_name,
                dispatch_plan_item_relations_attributes: create_item_relation_context(dpir, adjustment),
                timelines_attributes: [{
                    timeline_type: "dispatch",
                    deadline: dispatch_date,
                    status: Timeline.statuses[:open],
                    follow_up_date: Date.today
                                        },
                    {
                    timeline_type: "delivery",
                    deadline: delivery,
                    status: Timeline.statuses[:open],
                    follow_up_date: delivery - 1.day
                    }]

            }
    }
    {dp: dp_content}
end

def create_dp(dpir, adjustment)
    dp = dpir.dispatch_plan
    p "#{dp.id}, #{dpir.id}, #{adjustment}"
    dispatch_plan_service = DispatchPlanServices::Create.new(create_dispatch_plan_context(dp, dpir, adjustment))
    p "#{dispatch_plan_service}"
    dispatch_plan_service.execute!
end
=end
    '''
def remove_hanging_quantity(data)
    adjustments_made = []
    data.each do |reference|
        po_id = reference[0]
        po_item_id = reference[1]
        total_quantity = reference[2]
        actual_dp_sum = 0


        DispatchPlanItemRelation.where(bizongo_po_item_id: po_item_id).each do |dpir|
            if dpir.shipped_quantity == 0
                actual_dp_sum += dpir.quantity
            else
                actual_dp_sum += dpir.shipped_quantity
            end
        end

        if total_quantity >= actual_dp_sum
            adjustment = total_quantity - actual_dp_sum
            #create_dp(ref_dpir,adjustment)

                DispatchPlanItemRelation.where(bizongo_po_item_id: po_item_id).each do |dpir|
                dpir.hanging_quantity = 0
                dpir.hanging_dpir_ids = nil
                dpir.save
                end

            adjustments_made.push([po_id, po_item_id, adjustment])

        elsif total_quantity < actual_dp_sum
            p "PO Item ID: #{po_item_id} is serving excess quantity by #{actual_dp_sum - total_quantity} already"
        else
            p "PO Item ID: #{po_item_id} is alright"
        end

    end
    adjustments_made
end

