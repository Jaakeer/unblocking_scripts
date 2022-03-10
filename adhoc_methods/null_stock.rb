def null_stock(skus)
  stock_data = []
  skus.each do |sku_code|
    sku = MasterSku.where(sku_code: sku_code).first
    WarehouseSkuStock.where(master_sku_id: sku.id).each do |stock|
      current_stock = stock.open_stock
      warehouse_id = stock.warehouse_id
      sku_id = sku.id
      stock.open_stock = 0
      stock.save(validate: false)
      stock_data.push([sku_id, current_stock, warehouse_id])
    end
  end
  stock_data
end

def reinstate_stock(stock_data)
  stock_data.each do |stock_info|
    sku_id = stock_info[0]
    current_stock = stock_info[1]
    warehouse_id = stock_info[2]
    warehouse_stock = WarehouseSkuStock.where(warehouse_id: warehouse_id, master_sku_id: sku_id).first
    warehouse_stock.open_stock = current_stock
    warehouse_stock.save(validate: false)
  end
end

dp_ids.each do |dp_id|
  dp = DispatchPlan.find(dp_id)
  p "Entering IF........"
  if dp.status == "cancelled"
    next
  else
    dp.suggested_transporter_id = 494
    dp.suggested_transporter_name = "Delhivery B2C"
    dp.save(validate: false)
    p "Suggestion Changed for DP ID: #{dp_id}"
  end
end
