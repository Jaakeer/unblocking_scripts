def execute(po_ids)
  final_dp_ids = []
  failed_po_ids = []
  unless po_ids.blank?
    po_ids.each do |po_id|

      sku_types = make_skus_norm(po_id)
      po = PurchaseOrder.find(po_id)
      if po.direct_orders.present?
        po.direct_orders.each do |dor|
          final_dp_id = create_dispatch_plan(dor.id)
          final_dp_ids.push(final_dp_id) if final_dp_id.present?
        end
      else
        output = create_delivery_group(po_id)
        delivery_group_id = output[0]
        failed_po_ids.push(output[1])
        if delivery_group_id != 0
          dor_id = create_dor(delivery_group_id)
          final_dp_id = create_dispatch_plan(dor_id) unless dor_id == 0
        end

        if sku_types.present?
          sku_types.each do |sku_type|
            sku = MasterSku.find(sku_type[0])
            type = sku_type[1]
            sku.sku_type = type
            sku.save!
          end
        end

        final_dp_ids.push(final_dp_id)
      end
    end

  end
  return final_dp_ids, failed_po_ids
end

def make_skus_norm(po_id)
  sku_types = []
  po = PurchaseOrder.find(po_id)
  po_items = po.purchase_order_items
  po_items.each do |po_item|
    sku = po_item.child_product.product.master_sku
    unless sku.sku_type == "norm"
      sku_types.push([sku.id, sku.sku_type])
      sku.sku_type == "norm"
      sku.save
    end
  end
  return sku_types
end

def create_delivery_group(po_id)

  purchase_order = PurchaseOrder.find(po_id)
  delivery_group_id = 0
  error_po_ids = []
  begin
    if purchase_order.delivery_groups.present?
      delivery_group_id = purchase_order.delivery_groups.first
      p "Delivery Group already exist #{delivery_group_id}"
    else
      request_params = define_params(purchase_order)

      delivery_group = DeliveryGroup.new(request_params)
      delivery_group.save

      if delivery_group.errors.present?
        error_po_ids.push(purchase_order.id)
        puts "DG, DR, DRI not created because of #{delivery_group.errors.full_messages.join(', ')}"
      else
        delivery_group_id = delivery_group.id
      end
    end

  rescue => e

    puts "DG, DR, DRI not created because of #{e}"
  end
  return delivery_group_id, error_po_ids
end

def define_params(po)
  po_params = {
      purchase_order_id: po.id,
      placed_from: "lead_plus",
      request_type: "immediate",
      delivery_requests_attributes: []
  }

  po.purchase_order_items.each do |item|
    po_item = {
        delivery_date: Time.now + 5.days,
        actual_shipping_address_id: po.purchase_order_bulk_attribute.try(:billing_address_id), # po.purchase_order_bulk_attribute.try(:billing_address_id)
        delivery_request_items_attributes: [
            {
                purchase_order_item_id: item.id,
                quantity: item.total_quantity,
            }
        ]
    }

    po_params[:delivery_requests_attributes] << po_item
  end

  return po_params
end

def create_dor(dg_id)

  delivery_group = DeliveryGroup.find(dg_id)

  error_dg_ids = []
  direct_order_id = 0
  begin
      dor = DirectOrder.where(delivery_group_id: delivery_group.id).where("status != ?", DirectOrder.statuses[:cancelled])
      if dor.blank?

        puts "-----------------------------Staring creation of DOR and OI for purchase order id #{delivery_group.id}-----------------------------"

        params = dor_params(delivery_group)

        direct_order_service = DirectOrderServices::CreateDirectOrdersFromDeliveryRequests.new(params)
        direct_order_service.execute

          if direct_order_service.errors.present?
            error_dg_ids << delivery_group.id
            puts "Direct order not created by service because of #{direct_order_service.errors.join(', ')}"
          else
            direct_order_id = direct_order_service.result.first.id
          end
      else
        p "Dor already exist #{dor.map(&:id)}"
      end
  rescue => e
    error_dg_ids << delivery_group.id
    puts "Direct order not created because of #{e}"
  end
  return direct_order_id
end

def dor_params(dg)
  dg_params = {
      delivery_group_id: dg.id,
      valid_delivery_requests_params: []
  }
  dg.delivery_requests.each do |dr|
    dr_params = {
        address_id: dr.actual_shipping_address_id,
        id: dr.id,
        delivery_date: dr.delivery_date
    }
    dr_items = []
    dr.delivery_request_items.each do |dri|
      warehouse_address_id = check_transition_address(dri.child_product.company.id)
      dr_items << {
          id: dri.id,
          child_product_id: dri.child_product_id,
          quantity_distribution: {
              warehouse: {
                  dispatch_date: DateTime.now,
                  delivery_quantity: dri.quantity,
                  warehouse_address_id: warehouse_address_id #warehouse address id is static. In this I'm creating the order items for Bangalore WE3 warehouse.
              }
          }
      }
    end
    dr_params[:delivery_request_items] = dr_items
    dg_params[:valid_delivery_requests_params] << dr_params
  end
  dg_params
end

def check_transition_address(supplier_id)
  address_id = 0
  case supplier_id
  when 9508
    address_id = 15343
  when 7746
    address_id = 16192
  when 9816
    address_id = 17718
  when 4606
    address_id = 17350
  when 14388
    address_id = 17718
  else
    address_id
  end
  return address_id
end

def create_dispatch_plan(direct_order_ids)
  dispatch_plan_id = []
  direct_order_ids.each do |direct_order_id|
  direct_order = DirectOrder.find(direct_order_id)
  error_dor_ids = []


  begin
      request_context =  {
          direct_order: {
              id: direct_order.id
          }
      }

      puts "-----------------------------Staring creation of DP and DPIR for DOR #{direct_order.id}-----------------------------"

      service_context = DirectOrderServices::CreateDirectOrderDispatchPlans.new(request_context)
      service_context.execute

      if service_context.errors.present?
        error_dor_ids << direct_order.id
        puts "DP not created by service for direct order id #{direct_order.id} because of #{service_context.errors.join(",")}"
      else
        dispatch_plan_id.push(service_context.result.try(:first).try(:id))
      end
  rescue => e
    error_dor_ids << direct_order.id
    puts "DP not created because of #{e}"
  end
  end
  return dispatch_plan_id
end

def find_dor(po_ids)
  dor_ids = []
  po_ids.each do |po_id|
    po = PurchaseOrder.find(po_id)
    dor_ids.push(po.direct_orders.map(&:id))
  end
  return dor_ids.flatten
end

def find_order_items(dor_ids)
  order_item_ids = []
  dor_ids.each do |dor_id|
    dor = DirectOrder.find(dor_id)
    order_item_ids.push(dor.order_items.map(&:id))
  end
  return order_item_ids.flatten
end

