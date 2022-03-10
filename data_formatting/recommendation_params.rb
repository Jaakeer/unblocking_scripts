# frozen_string_literal: true

def recommended_transporter_params(dispatch_plan_id)
  dispatch_plan = DispatchPlan.find(dispatch_plan_id)
  region_type = 'non-intracity'
  is_category_a_ppe_category = false
  if dispatch_plan.seller_to_warehouse? || dispatch_plan.buyer_to_warehouse?
    destination_warehouse_id = dispatch_plan.destination_address_id
  elsif dispatch_plan.warehouse_to_buyer? || dispatch_plan.warehouse_to_seller?
    origin_warehouse_id = dispatch_plan.origin_address_id
  elsif dispatch_plan.warehouse_to_warehouse?
    destination_warehouse_id = dispatch_plan.destination_address_id
    origin_warehouse_id = dispatch_plan.origin_address_id
  end

  if dispatch_plan.dispatch_plan_item_relations.first.bizongo_po_item_id.present?
    po_item_response = Bizongo::Communicator.bizongo_po_items_index({ ids: [dispatch_plan.dispatch_plan_item_relations.first.bizongo_po_item_id] })[:bizongo_po_items].first
    supplier_id = po_item_response[:bizongo_purchase_order][:supplier_id]
  end
  if dispatch_plan.dispatch_plan_item_relations.first.order_item_id.present?
    order_item_response = Bizongo::Communicator.order_items_index({
                                                                    ids: [dispatch_plan.dispatch_plan_item_relations.first.order_item_id], invoice_response: true
                                                                  })
    buyer_id = order_item_response[:direct_order][:buyer_company_id]
  end
  if dispatch_plan.origin_address.present? && dispatch_plan.origin_address.warehouse.present?
    warehouse_name = dispatch_plan.origin_address.warehouse.warehouse_name
  end
  dispatch_plan.dispatch_plan_item_relations.each do |dpir|
    product = Hashie::Mash.new(CataloguingService::Communicator.fetch_product(dpir.master_sku_id))
    category = Hashie::Mash.new(CataloguingService::Communicator.fetch_category(product.category_id))
    if category.category.hierarchy.first == 'Healthcare Solutions'
      is_category_a_ppe_category = true
      break
    end
  end
  request_params_for_lbh_and_wt = get_request_params_for_truck_size(dispatch_plan)
  lbh_wt_response = Hashie::Mash.new(LogisticsDispatcher::Communicator.get_lbh_and_weight(request_params_for_lbh_and_wt))

  context[:errors] << lbh_wt_response.error_messages if lbh_wt_response.error_messages.present?

  is_delhi_ncr_pickup_and_delivery = APP_CONFIG['delhi_ncr_pincodes'].include?(dispatch_plan.destination_address.pincode) && APP_CONFIG['delhi_ncr_pincodes'].include?(dispatch_plan.origin_address.pincode)

  if dispatch_plan.origin_address.city == dispatch_plan.destination_address.city || is_delhi_ncr_pickup_and_delivery
    region_type = 'intracity'
  end

  request_params = {
    "pickup_pincode": dispatch_plan.origin_address.pincode,
    "pickup_city": dispatch_plan.origin_address.city,
    "pickup_state": dispatch_plan.origin_address.state,
    "drop_pincode": dispatch_plan.destination_address.pincode,
    "delivery_city": dispatch_plan.destination_address.city,
    "delivery_state": dispatch_plan.destination_address.state,
    "dispatch_mode": dispatch_plan.dispatch_mode,
    "order_type": 'PREPAID', # Defined by clickpost
    "reference_number": dispatch_plan.id,
    "item": dispatch_plan.dispatch_plan_item_relations.map(&:get_product_name).join(', '),
    "invoice_value": dispatch_plan.dispatch_plan_item_relations.map { |dpir| dpir.total_buyer_amount.to_f }.sum,
    "delivery_type": 'FORWARD',
    "breadth": 10, # It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "length": 10, # It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "height": 10, # It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "weight": lbh_wt_response.blank? || lbh_wt_response.error_messages.present? || (lbh_wt_response.final_dead_wt.zero? && lbh_wt_response.final_vol_wt.zero?) ? 10 : get_weight_info(lbh_wt_response),
    "additional": {
      "custom_fields": [
        {
          key: 'ptl_or_ftl',
          value: dispatch_plan.ptl_or_ftl
        },
        {
          key: 'truck_size',
          value: dispatch_plan.truck_type
        },
        {
          key: 'dispatch_mode',
          value: dispatch_plan.dispatch_mode
        },
        {
          key: 'supplier_id',
          value: supplier_id
        },
        {
          key: 'buyer_id',
          value: buyer_id
        },
        {
          key: 'origin_warehouse_id',
          value: origin_warehouse_id
        },
        {
          key: 'dispatch_plan_quantity',
          value: dispatch_plan.dispatch_plan_item_relations.sum(:quantity).to_f
        },
        {
          key: 'region',
          value: dispatch_plan.region
        },
        {
          key: 'warehouse_name',
          value: warehouse_name
        },
        {
          key: 'vehicle_type',
          value: dispatch_plan.truck_type
        },
        {
          key: 'region_type',
          value: region_type
        },
        {
          key: 'no_of_packages',
          value: is_category_a_ppe_category ? 1 : calculate_no_of_packages(dispatch_plan)
        },
        {
          key: 'gstin_status',
          value: dispatch_plan.destination_address.gstin.present?.to_s
        }
      ]
    }
  }
  result = Hashie::Mash.new(request_params)
  pretty_json(result)
end

def pretty_json(result)
  puts JSON.pretty_generate(result).gsub('=>', ': ').gsub('nil', 'null')
end

def get_request_params_for_truck_size(dispatch_plan)
  request = []

  dispatch_plan.dispatch_plan_item_relations.each do |dpir|
    params = {
      product_id: dpir.master_sku_id,
      quantity: dpir.quantity
    }
    request << params
  end
  request
end

def get_weight_info(lbh_wt_response)
  if lbh_wt_response.final_dead_wt.present? && lbh_wt_response.final_vol_wt.present?
    final_vol_wt = (lbh_wt_response.final_vol_wt * 28_316.8) / 4500
    lbh_wt_response.final_dead_wt >= final_vol_wt ? lbh_wt_response.final_dead_wt : final_vol_wt
  else
    lbh_wt_response.final_dead_wt.present? ? lbh_wt_response.final_dead_wt : lbh_wt_response.final_vol_wt
  end
end

def calculate_no_of_packages(dispatch_plan)
  no_of_packages = 0
  dispatch_plan.dispatch_plan_item_relations.each do |dpir|
    product_details = Hashie::Mash.new(LogisticsDispatcher::Communicator.fetch_product_metrics(dpir.master_sku_id))
    no_of_packages += dpir.shipped_quantity.to_f / product_details.bundle_quantity
  end
  no_of_packages
end

