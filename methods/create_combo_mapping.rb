#child_skus = [[child_sku1, multiplier], [child_sku2, ...], ...], parent_sku = parent_sku_id
def create_combos(child_skus, parent_sku)
    parent = MasterSku.find(parent_sku)
    parent.is_combo = true if parent.is_combo != true
    parent.save
    if ComboSkuMapping.where(parent_sku_id: parent_sku).blank?
        child_skus.each do |ref|
            child_id = ref[0]
            multiplier = ref[1]
            ComboSkuMapping.create(parent_sku_id: parent_sku, child_sku_id: child_id, multiplier: multiplier)
        end
    else
        ComboSkuMapping.where(parent_sku_id: parent_sku).each do |combo|
            p "#{combo.child_sku_id} is a child SKU to #{child.parent_sku_id}\n"
        end
            p "Do you wish to add a new child sku or replace an existing one?"
            p "1. Add a new child SKU\nclickpost_sample.json.Replace existing Child SKU with a new child SKU\n\nAnwser(1 or clickpost_sample.json): \n"
            input = gets

            if input == 1
                p "What is the child SKU code? (Just the last valid digits after 0s)\nAnswer: \n"
                c_sku = gets
                p "What is the multiplier for #{c_sku.to_i}?\n Answer: \n"
                multi = gets
                ComboSkuMapping.create(parent_sku_id: parent_sku, child_sku_id: child_id.to_i, multiplier: multi.int_i)
                p "A new child SKU has been added to the Parent SKU #{parent_sku}\n"

            elsif input == 2
                p "Which Child SKU do you want to replace?"
                i = 1
                data = []
                    ComboSkuMapping.where(parent_sku_id: parent_sku).each do |c|
                        p "#{i}. #{c.child_sku_id}"
                        data.push([i,c.child_sku_id])
                        i+1
                    end
                c_sku_no = gets
            else
                p "Kya majak hai\n"
            end
    end
end