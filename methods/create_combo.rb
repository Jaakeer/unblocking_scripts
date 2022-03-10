#child_skus = [[sku_id1, multiplier], [shu_id2, multiplier],..]

def create_combo(parent_sku, child_skus)
  sku = MasterSku.find(parent_sku)
  #change_sku_type([parent_sku])
  if sku.combo_sku_mappings.present? || sku.is_combo == true
    return false
  else
    child_skus.each do |ref|
      child_sku = ref[0]
      multiplier = ref[1]
      p "Child SKU: #{child_sku}"
      p "Multiplier: #{multiplier}"
      ComboSkuMapping.create(parent_sku_id: parent_sku, child_sku_id: child_sku, multiplier: multiplier)
      p "Added to combo #{parent_sku}"
    end
    sku.is_combo = true
    return sku.save
  end
end

def change_sku_type(skus)
  skus.each do |sku_id|
    sku = MasterSku.find(sku_id)
    if sku.sku_type == "non_norm"
      p "Already Non Norm"
    else
      sku.sku_type = "non_norm"
      sku.save!
      p "Changed the sku type to Non Norm for SKU: #{sku_id}"
    end
  end
end
