#input_data = [[dispatch_plan_id1, order_item_id1, address_id1], [dispatch_plan_id2, order_item_id2, address_id2], ..............]

def change_dispatch_mode(input_data)
  input_data.each do |ref_data|
    dispatch_plan_id = ref_data[0]
    order_item_id = ref_data[1]
    address_id = ref_data[2]
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    dpir = dispatch_plan.disptach_plan_item_relations.first
    if dispatch_plan.shipment.present? || dispatch_plan.dispatch_mode == "seller_to_buyer"
      p "xxxxxxxxxx:: Dispatch Plan (#{dispatch_plan.id}) is already Seller to Buyer or a shipment has been created for it, please review ::xxxxxxxxxx"
    else
      p "-------------------------Starting for DP ID: #{dispatch_plan.id}-------------------------"
      begin
        dispatch_plan.destination_address_id = address_id
        p ">>>>>>>> Address changed to buyer address using ID: #{address_id}"
        dispatch_plan.dispatch_mode = "seller_to_buyer"
        p ">>>>>>>> Mode changed to 'Seller to Buyer'"
        if dispatch_plan.save!
          dpir.order_item_id = order_item_id
          p ">>>>>>>> Order Item ID: #{order_item_id} attached"
          p "-------------------------Dispatch mode changed successfully for #{dispatch_plan.id}-------------------------" if dpir.save!
        end
      rescue => e
        p "Something went wrong while updating the dispatch mode, ERROR: #{e}"
      end
    end
  end
end

# Copy and paste the above code in SupplyChain Backend
# Prepare your input_data like mentioned in the first line
# Type: change_dispatch_mode(input_data)

def get_li_info(dp_id)
  dp = DispatchPlan.find(dp_id)
  dp.dispatch_plan_item_relations.each do |dpir|
    p ":::::::::::::::::::: For DPIR ID: #{dpir.id} Master SKU: #{dpir.master_sku_id} Total Quantity: #{dpir.shipped_quantity} ::::::::::::::::::::"
    if dpir.lot_informations.blank?
      p "-------------------- No Lot Information found, Master SKU: #{dpir.master_sku_id} --------------------"
    else
      dpir.lot_informations.each do |li|
        p "id: #{li.id}"
        p "lot_number: #{li.lot_number}"
        p "quantity: #{li.quantity}"
        p "warehouse_id: #{li.warehouse_id}"
        p "master_sku_id: #{li.master_sku_id}"
        p "is_valid: #{li.is_valid}"
        p "inward: #{li.inward}"
        p "-------------------------------------"
      end
    end
  end
  return nil
end


