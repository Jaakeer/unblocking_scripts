'''
=begin
Run the below method and keep the list of created products and child products
Output format will be [[product_id1, child_product_id1], [product_id1, child_product_id2], ...]
use the output later to deactivate all the products once the outwards are complete
Use method deactivate_products(used_products)
=end
'''
def create_new_products(skus)
    new_products = []
    skus.each do |sku_code|
        sku = MasterSku.where(sku_code: sku_code).first
        ref_product = Product.where(master_sku_id: sku.id).where(active: true).first
        ref_params = sku_params(ref_product)

        service = ProductServices::CreateSku.new(sku_params)
            begin
                 context = service.execute!
                 if context.errors.blank?
                    p "Product created, #{context.product_id}"
                    new_product_id = context.product_id
                    ref_product.child_products.where(active: true).each do |ref_child_product|
                        ref_child_product_params = child_product_params(ref_child_product, new_product_id)
                        child_context = ProductServices::CreateChildProductV3.new ref_child_product_params
                        begin
                            child_context.execute!
                            new_child_product = ChildProduct.find(child_context.child_product_id)
                            if child_context.errors.present? && new_child_product.blank?
                                p "Child Product is not created #{child_context.errors}"
                            else
                                ref_catalogue_id = ref_child_product.catalogue_child_product_relations.first.catalogue_id
                                new_child_product.catalogue_child_product_relations.create(catalogue_id: ref_catalogue_id)
                                p "New child product for product #{new_product_id} is created ID: #{new_child_product.id}"
                                new_products.push([new_product_id, new_child_product.id])
                            end
                        rescue => e
                                p "Something went wrong!!"
                            next
                        end
                    end
                 else
                    p "#{context.errors}"
                 end
            rescue => e
                p "Something went wrong while preparing product params"
                next
            end
    end
    new_products
end

def sku_params(product)
    new_product_matrix = ProductMatrix.where(product_id: product.id).first
    new_product_matrix.value = "1"

    new_product = {}
    new_product =
                {
                  base_product_id: product.base_product_id,
                  length: product[:length],
                  width: product[:width],
                  height: product[:height],
                  product_matrices: new_product_matrix,
                  on_request: product[:on_request],
                  sample: product[:sample],
                  master_sku_id: product[:master_sku_id]

                }
    return {product: new_product}
end

def child_product_params(child_product, new_product_id)
    child_params = {}
    child_params =
    {
        minimum_quantity: child_product.minimum_quantity,
        maximum_quantity: child_product.maximum_quantity,
        seller_price: child_product.seller_price,
        seller_price_per_unit: child_product.seller_price_per_unit,
        stock: child_product.stock,
        weight: child_product.weight,
        marketing_charge: child_product.marketing_charge,
        active: child_product.active,
        cod_enable: child_product.cod_enable,
        seller_delivery_charge: child_product.seller_delivery_charge,
        product_id: new_product_id,
        payment_terms: child_product.payment_terms,
        company_id: child_product.company_id,
        delivery_details: child_product.delivery_details,
        packaging_details: child_product.packaging_details,
        on_request: child_product.on_request,
        bulk_discounts: child_product.bulk_discounts,
        return_policy: child_product.return_policy,
        return_accepted_days: child_product.return_accepted_days,
        estimated_dispatch_days: child_product.estimated_dispatch_days,
        sample: child_product.sample,
        gst_percentage: child_product.gst_percentage
    }
    return {child_product: child_params}
end

def deactivate_products(used_products)
   '''
   Method...
   '''
end