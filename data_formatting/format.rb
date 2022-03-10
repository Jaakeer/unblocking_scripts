def recommended_transporter_params(dispatch_plan_id)
  dispatch_plan = DispatchPlan.find(dispatch_plan_id)
  if dispatch_plan.seller_to_warehouse? || dispatch_plan.buyer_to_warehouse?
    destination_warehouse_id = dispatch_plan.destination_address_id
  elsif dispatch_plan.warehouse_to_buyer? || dispatch_plan.warehouse_to_seller?
    origin_warehouse_id = dispatch_plan.origin_address_id
  elsif dispatch_plan.warehouse_to_warehouse?
    destination_warehouse_id = dispatch_plan.destination_address_id
    origin_warehouse_id = dispatch_plan.origin_address_id
  end

  if dispatch_plan.dispatch_plan_item_relations.first.bizongo_po_item_id.present?
    po_item_response = Bizongo::Communicator.bizongo_po_items_index({ids: [dispatch_plan.dispatch_plan_item_relations.first.bizongo_po_item_id]})[:bizongo_po_items].first
    supplier_id = po_item_response[:bizongo_purchase_order][:supplier_id]
  end
  if dispatch_plan.dispatch_plan_item_relations.first.order_item_id.present?
    order_item_response = Bizongo::Communicator.order_items_index({ids: [dispatch_plan.dispatch_plan_item_relations.first.order_item_id], invoice_response: true})
    buyer_id = order_item_response[:direct_order][:buyer_company_id]
  end
  if dispatch_plan.origin_address.present? && dispatch_plan.origin_address.warehouse.present?
    warehouse_name = dispatch_plan.origin_address.warehouse.warehouse_name
  end

  request_params = {
    "pickup_pincode": dispatch_plan.origin_address.pincode,
    "pickup_city": dispatch_plan.origin_address.city,
    "pickup_state": dispatch_plan.origin_address.state,
    "drop_pincode": dispatch_plan.destination_address.pincode,
    "delivery_city": dispatch_plan.destination_address.city,
    "delivery_state": dispatch_plan.destination_address.state,
    "dispatch_mode": dispatch_plan.dispatch_mode,
    "order_type": "PREPAID", #Defined by clickpost
    "reference_number": dispatch_plan.id,
    "item": dispatch_plan.dispatch_plan_item_relations.map{ |dpir| dpir.get_product_name }.join(', '),
    "invoice_value": dispatch_plan.dispatch_plan_item_relations.map{ |dpir| dpir.total_buyer_amount.to_f }.sum(),
    "delivery_type": "FORWARD",
    "breadth": 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "length": 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "height": 10, #It is madatory for clickpost API but they don't use this to calculate anything, they asked us to send any number.
    "weight": 10,
    "additional": {
      "custom_fields": [
        {
          key: "ptl_or_ftl",
          value: dispatch_plan.ptl_or_ftl
        },
        {
          key: "truck_size",
          value: dispatch_plan.truck_type
        },
        {
          key: "dispatch_mode",
          value: dispatch_plan.dispatch_mode
        },
        {
          key: "supplier_id",
          value: supplier_id
        },
        {
          key: "buyer_id",
          value: buyer_id
        },
        {
          key: "origin_warehouse_id",
          value: origin_warehouse_id
        },
        {
          key: "dispatch_plan_quantity",
          value: dispatch_plan.dispatch_plan_item_relations.sum(:quantity).to_f
        },
        {
          key: "region",
          value: dispatch_plan.region
        },
        {
          key: "warehouse_name",
          value: warehouse_name
        },
        {
          key: "vehicle_type",
          value: dispatch_plan.truck_type
        }
      ]
    }
  }
  result = Hashie::Mash.new(request_params)
  result
end