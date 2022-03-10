def create_all_child_products(master_sku)
    for i in master_sku do
        products = MasterSku.where(sku_code: i).last.products.map {|sku| sku.id}
        for j in products do
            if Product.find(j).active == true
                child_products = Product.find(j).child_products.map {|child| [child.id, child.company_id]}




companies = [9816, 9508, 4606, 7746, ]





def child_product_params(child_product, entity)
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
        company_id: entity,
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

def create_new_child(master_sku)
    for i in master_sku do
        products = MasterSku.where(sku_code: i).last.products.map(&:id)
        for j in products do
            product = Product.find(j)
            if product.active == true && product.sample == false && product.child_products.present?
                bizongo_entity = [9816, 9508, 4606, 7746, 18617]
                sample_child_product = product.child_products.where(sample: false).last
                catalogue = product.child_products.map {|c| c.catalogue_child_product_relations.map(&:catalogue_id)}.uniq
                companies = product.child_products.map(&:company_id)
                companies = companies.uniq
                bizongo_entity = (bizongo_entity - companies)
                if bizongo_entity.blank?
                    if catalogue[0][0] != 0
                        catalog = catalogue[0][0]
                    else
                        catalog = catalogue[1][0]
                    end
                    product.child_products.each do |children|
                        if children.catalogue_child_product_relations.blank?
                            children.catalogue_child_product_relations.create(catalogue_id: catalog)
                            puts "Child product #{children} with new catalogue ID"
                        else
                            puts "Child product #{children.id} is already mapped with catalog"
                        end
                    end
                elsif sample_child_product.present?
                    for entity in bizongo_entity do
                    request_params = child_product_params(sample_child_product, entity)
                    request_params[:company_id] = entity
                    catalog = catalogue[0][0]
                    @context = ProductServices::CreateChildProductV3.new request_params
                        begin
                            @context.execute!
                            new_child_product = product.child_products.where(company_id: entity).first
                            if new_child_product.blank?
                                puts "Child Product is not created"
                            else
                                new_child_product.catalogue_child_product_relations.create(catalogue_id: catalog)
                                puts "Product #{j} has new child product #{new_child_product.id}"
                            end
                        rescue => e
                                p "Something went wrong!!"
                            next
                        end
                    end
                else
                    puts "All sample child products present"
                end
            else
                puts "Product id #{j} is not active or no child ID is present for sample"
                next
            end
        end
    end
end


def delete_catalog(master_skus)
    for i in master_skus do
        products = MasterSku.where(sku_code: i).last.products.map {|sku| sku.id}
        for j in products do
            product = Product.find(j)
            if product.active == true && product.child_products.present?
                catalogue = product.child_products.map {|c| c.catalogue_child_product_relations.map {|cp| cp.id}}.uniq
                for child in product.child_products do
                    if catalogue[0][0] != 0
                        catalog = catalogue[0][0]
                    else
                        catalog = catalogue[1][0]
                    end
                    for ch in child.catalogue_child_product_relations do
                        if ch.catalogue_id == catalog
                            ch.destroy
                        else
                            next
                        end
                    end
                end
            else
                next
            end
        end
    end
end

def create_new_child(master_sku)
    for i in master_sku do
        products = MasterSku.where(sku_code: i).last.products.map {|sku| sku.id}
        for j in products do
            product = Product.find(j)
            catalog_id = 0
            if product.active == true && product.sample == false && product.child_products.present?
                product.child_products.each do |child|
                    if child.catalogue_child_product_relations.present?
                        catalog_id = child.catalogue_child_product_relations.first.catalogue_id
                    end
                    if child.catalogue_child_product_relations.blank? && catalog_id != 0
                        child.catalogue_child_product_relations.create(catalogue_id: catalog_id)
                        puts "#{child} is mapped to #{Catalogue.find(catalog_id).name}"
                    else
                        puts "#{product} does not have any catalog ID"
                    end
                end
            end
        end
    end
end