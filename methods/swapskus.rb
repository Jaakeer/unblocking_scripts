def swapsku(ref_sku_data, new_sku_data)
    ref_sku_data.each do |sku1|
        old_sku_id = MasterSku.where(sku_code: sku1).first.id
        new_sku_data.each do |sku2|
            new_sku_id = MasterSku.where(sku_code: sku2).first.id
            product = Product.where(master_sku_id: old_sku_id).last
            if product.present?
                product.master_sku_id = new_sku_id
                product.save
            else
                next
            end
        end
    end
end