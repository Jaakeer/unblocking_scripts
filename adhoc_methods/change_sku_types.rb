# frozen_string_literal: true

# input:
# skus = [master_sku_id1, master_sku_id2, ...]
# sku_type = "norm" / "non_norm" / "direct"
def change_sku_types(skus, sku_type)
  skus.each do |sku_id|
    sku = MasterSku.find(sku_id)
    if sku.sku_type == sku_type
      p "The SKU: #{sku_id} is already #{sku_type}"
    else
      sku.sku_type = sku_type
      sku.save!
      p "Changed the sku type to #{sku_type} for SKU: #{sku_id}"
    end
  end
end

# e.g. change_sku_types(skus, "direct")
