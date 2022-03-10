def child_product_params(child_product)
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
        product_id: child_product.product_id,
        payment_terms: child_product.payment_terms,
        company_id: 7746,
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

def create_new_child(master_sku, bizongo_entity)
    for i in master_sku do
        products = MasterSku.where(sku_code: i).last.products.map {|sku| sku.id}
        for j in products do
            product = Product.find(j)
            if product.active == true
                child_products = product.child_products.map {|child| [child.id, child.company_id]}
                companies = product.child_products.map {|child| child.company_id}
                companies = companies.uniq
                bizongo_entity = (bizongo_entity - companies)
                flag = 0
                for k in child_products do
                    child_id = k[0]
                    company_id = k[1]
                    if company_id == bizongo_entity
                    flag = flag + 1
                    else
                        next
                    end
                end

                if flag == 0
                    sample_child_product = ChildProduct.find(child_id)
                    request_params = child_product_params(sample_child_product)
                    request_params[:bulk_discounts] = child_product_params(sample_child_product)[:bulk_discounts]
                    request_params[:company_id] = 7746
                    catalogue = sample_child_product.catalogue_child_product_relations.last
                    @context = ProductServices::CreateChildProductV3.new request_params
                    @context.execute!
                    new_child_product = product.child_products.where(company_id: bizongo_entity).first
                    if new_child_product.blank?
                        puts "Child Product is not created"
                    else
                        new_child_product.catalogue_child_product_relations.create(catalogue_id: catalogue.id)
                    end
                else
                    puts "Child product with Smartpaddle Mumbai entity already exist for #{child_id}"
                end
            else
                puts "Product id #{j} is not active"
                next
            end
        end
    end
end

