#master_skus = Centre.where(company_id: 6723).first.catalogue.products.map(&:master_sku_id).uniq

def calculate(master_sku_id)
  oldest_date = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").first.created_at.to_date
  latest_date = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).last.created_at.to_date

  total_orders = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).map(&:shipped_quantity)
  count = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).count

  total_days = (latest_date - oldest_date).to_i
  total_order_qty = total_orders.sum()
  average_daily_consumption = (total_order_qty / count).round(2)
  standard_deviation = find_std_dev(total_orders, average_daily_consumption, total_days)

  p "Total number of days: #{total_days}"
  p "Total Ordered Quantity: #{total_order_qty}"
  p "The average daily consumption: #{average_daily_consumption}"
  p "The standard deviation: #{standard_deviation}"

  last_three_month = last_three_months(master_sku_id)
  p "The safety standard deviation: #{last_three_month}"
end

def last_three_months(master_sku_id)
  three_months = DateTime.now - 3.month
  no_of_days = (DateTime.now - three_months).to_int
  total_orders = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", three_months).map(&:shipped_quantity)
  total_quantity = total_orders.sum()
  average_daily_consumption = total_quantity / no_of_days
  average_daily_consumption = average_daily_consumption.round(2)
  p "Average Daily consumption for last three months: #{average_daily_consumption}"
  standard_deviation = find_std_dev(total_orders, average_daily_consumption, no_of_days)
  standard_deviation
end

def find_std_dev(total_shipped_orders, average_daily_consumption, total_days)
  total_variance = 0
  total_shipped_orders.each do |shipped_quantity|
    variance = (shipped_quantity - average_daily_consumption) ** 2
    total_variance += variance
  end
  std_dev = total_variance / total_days
  return Math.sqrt(std_dev).round(2)
end
