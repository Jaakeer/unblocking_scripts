def update_weight_info(weight_data)
  ticker = 1
  weight_data.each do |ref|
    p "#{ticker}. Starting with Master SKU: #{ref[0]}..."
    #populate input data
    sku_code = ref[0]
    pack_size = ref[1]
    l = ref[2]
    b = ref[3]
    h = ref[4]
    dead_weight = ref[5]
    counter = 1

    #change weight info
    MasterSku.where(sku_code: sku_code).first.products.each do |product|
      begin
        product.length_in_cm = l
        product.breadth_in_cm = b
        product.height_in_cm = h
        product.dead_weight = dead_weight
        product.pack_size = pack_size
        product.save!

        #change pack size
        product.product_matrices.each do |pm|
          pm.value = pack_size
          pm.save!
        end
        p "---#{counter}. Weight information updated for product ID: #{product.id}"
        counter = counter + 1
      rescue => e
        p "---#{counter}. Weight info cannot be updated due to #{e}"
      end
    end
    ticker = ticker + 1
  end
end

def change_pack_size(sku_code, pack_size)
  sku = MasterSku.find(sku_code)
  sku.products.each do |p|
    p.product_matrices.first.update(value: pack_size)
    p.update(pack_size: pack_size)
  end
end