###### For Bizongo Backend

# Urban Company centre: 19302

def automate_dp(centre_id)
  PurchaseOrder.where(centre_id: centre_id).each do |po|
    direct_order_ids = po.direct_orders.map(&:id)
    create_dp_for_dor(direct_order_ids)
  end
end

# Automate DP creation for DORs
# dor_ids = [dor_ids1, dor_id2, dor_id3, ...]
def create_dp_for_dor(dor_ids)
  dor_ids.each do |direct_order_id|
    p "Starting for Direct Order ID: #{direct_order_id}"
    direct_order = DirectOrder.find(direct_order_id)
    CreateCheckpointForDirectOrderWorker.perform_later(direct_order.id, source: "order_automation")
  end
end

# If you want to create DPs manually you can change the request types
# delivery_group_id is pretty id of the delivery group
def make_dg_manual(delivery_group_id)
  delivery_group = DeliveryGroup.where(pretty_id: delivery_group_id).first
  delivery_group.request_types = "immediate"
  delivery_group.save!
  p "Delivery Group (#{delivery_group_id}) can be manually processed now"
end

# Change SKU type to "norm", "non_norm", "direct" whenever needed
def change_sku_type(master_sku_id, sku_type)
  sku = MasterSku.find(master_sku_id)
  sku.sku_type = sku_type
  sku.save!
  p "SKU Type for master SKU: #{master_sku_id} changed to #{sku.sku_type}"
end

def find_skus(catalogue_id)
  child_product_ids = CatalogueChildProductRelation.where(catalogue_id: catalogue_id).map(&:child_product_id)
  master_sku_ids = []
  child_product_ids.each do |child_product_id|
    child_product = ChildProduct.find(child_product_id)
    product = child_product.product
    master_sku_ids.push(product.master_sku_id)
  end
  return master_sku_ids.uniq
end

###### For Supply chain

# Increase Stock for a Master SKU
#
def increase_stock(master_sku_ids)
  master_sku_ids.each do |master_sku_id|
    Warehouse.all.each do |w|
      next if w.active = false
      wh_stock = WarehouseSkuStock.where(master_sku_id: master_sku_id, warehouse_id: w.id).first
      if wh_stock.present?
        wh_stock.open_stock = 300000
        wh_stock.save!
      else
        LotInformation.where(master_sku_id: master_sku_id, warehouse_id: w.id, inward: true, is_valid: true).each do |li|
          next if li.nil?
          li.lot_information_locations.each do |lil|
            if lil.is_valid = true
              lil.remaining_quantity = 300000
              lil.save(validate: false)
            end
          end
        end
      end
    end
  end
end

