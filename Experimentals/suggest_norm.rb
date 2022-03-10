def suggest_norm(input)
  norm = "Norm Value"
  p "Do something with #{input}"
  return norm
end

def testing
  company_id = 6723
  master_sku_id = 30712
  company = Company.find(company_id)
  data = Hash.new
  company.centres.each do |centre|
    centre.catalogue.products.each do |product|
      next if product.active == false
      if product.master_sku_id == master_sku_id
        child_product_ids = product.child_products.active.map(&:id)
        data.push([centre.id, master_sku_id, product.id, child_product_ids])

      end
    end
  end

end

#master_skus = Centre.where(company_id: 6723).first.catalogue.products.map(&:master_sku_id).uniq
def calculate(master_sku_id)
  oldest_date = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).first.created_at.to_date

  count = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).count

  latest_date = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).last.created_at.to_date

  total_orders = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", oldest_date).map(&:shipped_quantity)

  total_days = (latest_date - oldest_date).to_i
  total_order_qty = total_orders.sum()
  average_daily_consumption = (total_order_qty / count).round(2)
  standard_deviation = find_std_dev(total_orders, average_daily_consumption, count)

  p "Total number of days: #{total_days}"
  p "Total Ordered Quantity: #{total_order_qty}"
  p "The average daily consumption: #{average_daily_consumption}"
  p "The standard deviation: #{standard_deviation}"

  last_three_month = last_three_months(master_sku_id)
  p "The safety standard deviation: #{last_three_month}"
end

def last_three_months(master_sku_id)
  three_months = Datetime.now - 3.month
  no_of_days = (DateTime.now - three_months).to_int
  total_orders = DispatchPlanItemRelation.filter(master_sku_id: master_sku_id, dispatch_plan_status: "done", dispatch_mode: "warehouse_to_buyer").
      where("dispatch_plan_item_relations.created_at > ?", three_months).map(&:shipped_quantity)
  average_daily_consumption = total_orders / no_of_days
  standard_deviation = find_std_dev(total_orders, average_daily_consumption, count)
  standard_deviation
end

def find_std_dev(total_orders, average_daily_consumption, count)
  total_variance = 0
  total_orders.each do |shipped|
    variance = (shipped - average_daily_consumption) ** 2
    total_variance += variance
  end
  std_dev = total_variance / count
  return Math.sqrt(std_dev).round(2)
end

