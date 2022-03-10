def reserve_stock(sku_id)
  WarehouseSkuStock.where(master_sku_id: sku_id).each do |wsku|
    reserved_stock = wsku.reserved_stock
    address_id = wsku.warehouse.address.id
    open_dispatch_plan_quantity = DispatchPlan.open.warehouse_to_buyer.where("pick_list_file is null and origin_address_id = ? and dispatch_plans.description in (?)", address_id, ['auto_created', 'Create by system']).sum {|dp| dp.dispatch_plan_item_relations.where(master_sku_id: wsku.master_sku_id).sum(&:quantity)}.to_f
    if reserved_stock != open_dispatch_plan_quantity
      puts "Warehouse ID: #{wsku.warehouse_id}, MasterSKU: #{wsku.master_sku_id}, Warehouse Reserve Stock: #{reserved_stock}, DP total: #{open_dispatch_plan_quantity}"
      wsku.reserved_stock = open_dispatch_plan_quantity
      wsku.save!
    end
  end; nil
end


open_dispatch_plan_quantity = DispatchPlan.open.warehouse_to_buyer.where("pick_list_file is null and origin_address_id = ? and dispatch_plans.description in (?)", 16192, ['auto_created', 'Create by system']).sum {|dp| dp.dispatch_plan_item_relations.where(master_sku_id: 81).sum(&:quantity)}.to_f

data.each do |ref|
  li_id = ref[0]
  li = LotInformation.find(li_id)
  qty = li.quantity
  lot_no = li.lot_number
  inward_li = LotInformation.where(lot_number: lot_no, inward: true, is_valid: true).first
  inward_li.lot_information_locations.each do |lil|
    lil.remaining_quantity -= qty
    lil.save
  end
  WarehouseSkuStock.where(master_sku_id: li.master_sku_id, warehouse_id: li.warehouse_id).first.adjust
end

[{"version_number"=>2,
  "requester_admin"=>
      {"id"=>33983,
       "name"=>"Prince Thomas",
       "admin_user_type"=>"PG",
       "version_created_at"=>"2020-01-31"},
  "product_delivery_timelines"=>
      [{"id"=>"3c2r4gpvwce2p",
        "delivery_city"=>"Bangalore",
        "delivery_type"=>"seller_to_buyer",
        "delivery_pincode"=>560067,
        "delivery_address_id"=>26658,
        "delivery_quantity_date"=>
            [{"is_confirmed"=>true,
              "delivery_date"=>"2020-02-25",
              "delivery_quantity"=>32340}],
        "delivery_request_item_id"=>175300}]}]



{"po_item_gst"=>12.0,
 "product_name"=>
     "LCB3 | Tata Cliq Corrugated Box 23 cm x 10 cm x 10 cm | 5 Ply",
 "price_per_unit"=>22.0,
 "product_matrix"=>{"id"=>73654, "unit"=>"Boxes", "value"=>"1"},
 "product_specifications"=>
     {"GSM"=>"150x120x120x120x120",
      "Color"=>"Brown",
      "Material"=>"Top paper golden Kraft rest brown Kraft",
      "Printing"=>"1 Color",
      "Number of Ply"=>"5",
      "Width (in cm)"=>"10.000",
      "Height (in cm)"=>"10.000",
      "Length (in cm)"=>"23.000",
      "Bursting Factor"=>"24"},
 "delivery_price_per_unit"=>0.0}


{"po_item_gst"=>12.0,
 "product_name"=>
     "LCB2 | Tata Cliq Corrugated Box 20 cm x 12 cm x 10 cm | 5 Ply",
 "price_per_unit"=>37.0,
 "product_matrix"=>{"id"=>73651, "unit"=>"Boxes", "value"=>"1"},
 "product_specifications"=>
     {"GSM"=>"150x120x120x120x120",
      "Color"=>"Brown",
      "Material"=>"Top paper golden Kraft rest brown Kraft",
      "Printing"=>"1 Color",
      "Number of Ply"=>"5",
      "Width (in cm)"=>"12.000",
      "Height (in cm)"=>"10.000",
      "Length (in cm)"=>"20.000",
      "Bursting Factor"=>"24"},
 "delivery_price_per_unit"=>0.0}


open_dispatch_plan_quantity = DispatchPlan.open.warehouse_to_buyer.where("pick_list_file is null and origin_address_id = ? and dispatch_plans.description in (?)", address_id, ['auto_created', 'Create by system']).sum
{|dp| dp.dispatch_plan_item_relations.where(master_sku_id: 32052).sum(&:quantity)}.to_f