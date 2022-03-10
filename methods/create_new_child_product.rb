def create_new_child(master_sku, bizongo_entity)
    for i in master_sku do
        products = MasterSku.where(sku_code: i).last.products.map {|sku| sku.id}
        for j in products do
            if Product.find(j).active == true
                child_products = Product.find(j).child_products.map {|child| [child.id, child.company_id]}
                for k in child_products do
                    c_id = 0
                    child_id = k[0]
                    company_id = k[1]
                    if company_id != bizongo_entity
                        catalogue = ChildProduct.find(child_id).catalogue_child_product_relations.last
                        next
                    elseif company_id == bizongo_entity && ChildProduct.find(child_id).catalogue_child_product_relations.blank?
                        c_id = child_id
                    else
                        puts "Child ID #{child_id} already has a catalogue mapped"
                    end
                end
                if c_id != 0
                    ChildProduct.find(c_id).catalogue_child_product_relations.create(catalogue_id: catalogue.id)
                else
                    puts "Product #{j} already has all catalogues mapped"
                end
            else
                puts "Product id #{j} is not active"
                next
            end
        end
    end
end