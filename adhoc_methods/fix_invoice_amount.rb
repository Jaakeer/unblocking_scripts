# frozen_string_literal: true

def fix_invoice_amount(shipment_ids)
  counter = 1
  Shipment.where(id: shipment_ids).each do |shipment|
    next if shipment.seller_payment_status != 'pending' # || shipment.settled?

    seller_invoice_amount = 0
    buyer_invoice_amount = 0
    p "#{counter}. Starting with shipment: #{shipment.id}"
    begin
      dispatch_plan = shipment.dispatch_plan
      item_details = dispatch_plan_item_details(dispatch_plan)
      p '    Updating DPIR product detail snapshot.. '
      dispatch_plan.update_dpir_product_details(item_details)

      shipment.dispatch_plan_item_relations.each do |dpir|
        p "    Calculating individual DPIR amounts..[#{dpir.id}]"
        qty = (dpir.shipped_quantity - dpir.lost_quantity - dpir.returned_quantity)
        next if qty.zero?

        ppu = dpir.product_details['price_per_unit']
        gst = dpir.product_details['po_item_gst']
        order_item_ppu = dpir.product_details['order_price_per_unit']
        order_item_gst = dpir.product_details['order_item_gst']
        total_seller_amount = qty * ppu * (1 + (gst * 0.01))
        total_buyer_amount = (qty * order_item_ppu * (1 + (order_item_gst * 0.01))) + dpir.buyer_service_charge + dpir.buyer_service_charge_tax
        dpir.total_seller_amount = total_seller_amount
        dpir.total_buyer_amount = total_buyer_amount
        dpir.save!
        p "    DPIR amount updated SKU: #{dpir.master_sku_id}"
        seller_invoice_amount += total_seller_amount
        buyer_invoice_amount += total_buyer_amount
      end

      total_seller_invoice_amount = seller_invoice_amount + shipment.actual_charges
      total_seller_payable = total_seller_invoice_amount + shipment.seller_extra_charges
      total_buyer_invoice_amount = buyer_invoice_amount
      shipment.total_seller_invoice_amount = total_seller_invoice_amount
      shipment.total_seller_payable = total_seller_payable
      shipment.total_buyer_invoice_amount = total_buyer_invoice_amount
      shipment.total_buyer_receivable = total_buyer_invoice_amount
      shipment.save!
      p '    Updated Shipment invoice amount...'
      unless shipment.seller_invoice_id.nil?
        FinanceServiceDispatcher::Communicator.update_invoice(shipment.seller_invoice_id,
                                                              { skip_update_validation: true,
                                                                amount: seller_invoice_amount })
        p '    Updated Finance amount...'
      end
    rescue StandardError => e
      p "ERROR: Something went wrong: #{e}"
    end
    counter += 1
  end.nil?
end

def dispatch_plan_item_details(dispatch_plan)
  start_time = Time.now
  bizongo_po_items = []
  order_items = []
  bizongo_po_item_ids = dispatch_plan.dispatch_plan_item_relations.pluck(:bizongo_po_item_id)
  if bizongo_po_item_ids.compact.present?
    bizongo_po_items = PoServiceDispatcher::Communicator.get_purchase_order_items({
                                                                                    id: bizongo_po_item_ids.join(','), size: 100
                                                                                  })['items']
    bizongo_po_items.count
  end
  order_item_ids = dispatch_plan.dispatch_plan_item_relations.pluck(:order_item_id)
  if order_item_ids.compact.present?
    response = Hashie::Mash.new Bizongo::Communicator.order_items_index!({ ids: order_item_ids })
    order_items = response[:order_items]
  end
  end_time = Time.now

  Rails.logger.info "Execution time for method DispatchPlan::dispatch_plan_item_details - #{(end_time - start_time) * 1000} ms"
  { order_items: order_items, bizongo_po_items: bizongo_po_items }
end
