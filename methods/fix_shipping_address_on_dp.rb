def fix_add(final)
  for i in final do
    order_id = i[0]
    destination_add_id = i[1]
    dpir = DispatchPlanItemRelation.where(order_item_id: order_id)

    dp = dpir.sort.last.dispatch_plan

    dp.destination_address_id = destination_add_id
    dp.save(validate: false)
  end
end