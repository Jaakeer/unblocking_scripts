# frozen_string_literal: true

# @param [Object] dispatch_plan_ids
# @param [Object] fix_dpir_qty
def create_invoice(dispatch_plan_ids, fix_dpir_qty)
  # dispatch_plan_ids = [dispatch_plan_id1, dispatch_plan_id2,...]
  counter = 1
  begin
    dispatch_plan_ids.each do |dispatch_plan_id|
      dispatch_plan = DispatchPlan.find(dispatch_plan_id)
      next if dispatch_plan.shipment.nil?

      shipment = DispatchPlan.find(dispatch_plan_id).shipment

      fix_dpir(shipment) if fix_dpir_qty

      if shipment.buyer_invoice_id.present?
        begin
          p "#{counter}. Starting for DP: #{dispatch_plan.id}, Invoice: #{shipment.buyer_invoice_no}"
          create_invoice_id(dispatch_plan_id, false)

          p '..... Recalculating DPIR total amounts'
          # shipment.dispatch_plan_item_relations.each do |dpir|
          #  Finance::CalcDispatchPlanItemRelationTotalStatsJob.perform_now(dpir.id, false)
          # end;nil

          response = FinanceServiceDispatcher::Communicator.show_invoice(shipment.buyer_invoice_id)
          line_item_details = response[:line_item_details]
          p '..... Building Line Item data (If it takes time at this point, means line item array was blank and we are building it again)'

          if line_item_details == '[]'
            FinanceServiceDispatcher::Communicator.update_invoice(shipment.buyer_invoice_id,
                                                                  { skip_update_validation: true,
                                                                    line_item_details: get_line_item_details(shipment) })
            # FinanceServiceDispatcher::Communicator.update_invoice
            # (shipment.seller_invoice_id,{ skip_update_validation: true,entity_reference_number: "PO/FY22/BZMH/01513"})
          end

          amount = 0
          line_item_details.each do |line_item|
            dpir = DispatchPlanItemRelation.find(line_item['dispatch_plan_item_relation_id'])
            case dispatch_plan.dispatch_mode
            when 'warehouse_to_warehouse'
              line_item['price_per_unit'] = dpir.product_details['price_per_unit']
              line_item['tax_percentage'] = dpir.product_details['child_item_gst']
            when 'warehouse_to_buyer', 'seller_to_buyer'
              line_item['price_per_unit'] = dpir.product_details['order_price_per_unit']
              line_item['tax_percentage'] = dpir.product_details['order_item_gst']
            else
              break
            end
            line_item['hsn'] = dpir.product_details['hsn_number']
            amount_without_tax = line_item['quantity'].to_f * line_item['price_per_unit'].to_f
            line_item['amount_without_tax'] = amount_without_tax.to_f.round(2)
            amount += ((1 + line_item['tax_percentage'].to_f * 0.01) * line_item['quantity'].to_f * line_item['price_per_unit'].to_f)
          end
          p "..... Creating pricing information and creating invoice for shipment #{shipment.id}: #{shipment.buyer_invoice_no}"
          FinanceServiceDispatcher::Communicator.update_invoice(shipment.buyer_invoice_id,
                                                                { skip_update_validation: true,
                                                                  amount: amount.to_f.round(2), line_item_details: line_item_details })
          FinanceServiceDispatcher::Requester.new.post("invoices/#{shipment.buyer_invoice_id}/generate-e-invoice")
        rescue StandardError => e
          p "..... Something went wrong while creating the invoice #{e}"
        end
      else
        p "#{counter}. ERROR: No Shipment/invoice present for DP: #{dispatch_plan_id}"
        create_invoice_id(dispatch_plan_id, true)
      end
      counter += 1
    end; nil
  rescue StandardError => e
    p "#{counter}. Something went wrong while creating the invoice #{e}"
  end
end

def retry_invoice(dispatch_plan_ids)
  dispatch_plan_ids.each do |dispatch_plan_id|
    shipment = DispatchPlan.find(dispatch_plan_id).shipment
    FinanceServiceDispatcher::Communicator.update_invoice(shipment.buyer_invoice_id,
                                                          { skip_update_validation: true,
                                                            line_item_details: get_line_item_details(shipment) })
    if shipment.present?
      FinanceServiceDispatcher::Requester.new.post("invoices/#{shipment.buyer_invoice_id}/generate-e-invoice")
      p "Retrying for #{shipment.buyer_invoice_no}"
    else
      p "There is no Shipment for this DP: #{dispatch_plan_id}"
    end
  end
end

def get_line_item_details(shipment)
  dispatch_plan = shipment.dispatch_plan
  invoice_items = []
  dispatch_plan.dispatch_plan_item_relations.by_non_zero_shipped_quantity.each do |dispatch_plan_item_relation|
    if dispatch_plan.warehouse_to_warehouse?
      price_per_unit = dispatch_plan_item_relation[:product_details]['price_per_unit']
      tax_percentage = dispatch_plan_item_relation[:product_details]['child_item_gst']
    else
      price_per_unit = dispatch_plan_item_relation[:product_details]['order_price_per_unit']
      tax_percentage = dispatch_plan_item_relation[:product_details]['order_item_gst']
    end
    invoice_items << {
      item_name: dispatch_plan_item_relation[:product_details]['alias_name'].present? ? dispatch_plan_item_relation[:product_details]['alias_name'] : dispatch_plan_item_relation[:product_details]['product_name'],
      hsn: dispatch_plan_item_relation[:product_details]['hsn_number'],
      quantity: dispatch_plan_item_relation.shipped_quantity,
      price_per_unit: price_per_unit.to_f,
      tax_percentage: tax_percentage.to_f,
      amount_without_tax: (price_per_unit.to_f * dispatch_plan_item_relation.shipped_quantity).to_f.round(2),
      dispatch_plan_item_relation_id: dispatch_plan_item_relation.id,
      centre_product_id: dispatch_plan_item_relation.centre_product_id
    }
  end
  invoice_items
end

def fix_dpir(shipment)
  shipment.dispatch_plan_item_relations.each do |dpir|
    dpir.shipped_quantity = dpir.quantity
    dpir.expected_shipped_quantity = dpir.quantity
    dpir.save!
  end
end


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
      shipment.total_buyer_payable = total_buyer_invoice_amount
      shipment.save!
      p '    Updated Shipment invoice amounts...'
    rescue StandardError => e
      p "ERROR: Something went wrong: #{e}"
    end
    counter += 1
  end.nil?
end

def create_invoice_id(dispatch_plan_ids, generate)
  counter = 1
  dispatch_plan_ids.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    p "#{counter}. Starting with dispatch plan #{dispatch_plan.id}"
    update_dp_data(dispatch_plan)
    next if dispatch_plan.shipment.nil?
    if generate && dispatch_plan.shipment.buyer_invoice_no.nil?
      begin
        InvoiceServices::Create.new({ dispatch_plan_id: dispatch_plan.id }).execute!
        p ".... Updating details for #{dispatch_plan.id}, creating invoice for shipment #{dispatch_plan.shipment.id}"
      rescue StandardError => e
        p ".... Something went wrong with DP(#{dispatch_plan.id}): #{e}"
      end
    elsif dispatch_plan.shipment.buyer_invoice_no.present?
      p ".... Invoice(#{dispatch_plan.shipment.buyer_invoice_no}) already present for DP(#{dispatch_plan.id})"
      retry_invoice([dispatch_plan_id])
    end
    counter += 1
  end
end

def update_dp_data(dispatch_plan)
  item_details = dispatch_plan_item_details(dispatch_plan)
  update_dpir_product_details(item_details, dispatch_plan)
  dispatch_plan.update_company_snapshot(item_details)
end

def dispatch_plan_item_details(dispatch_plan)
  start_time = Time.now
  @bizongo_po_items = []
  @order_items = []
  bizongo_po_item_ids = dispatch_plan.dispatch_plan_item_relations.pluck(:bizongo_po_item_id)
  if bizongo_po_item_ids.compact.present?
    @bizongo_po_items = PoServiceDispatcher::Communicator.get_purchase_order_items({
                                                                                     id: bizongo_po_item_ids.join(','), size: 100
                                                                                   })['items']
    @bizongo_po_items.count
  end
  order_item_ids = dispatch_plan.dispatch_plan_item_relations.pluck(:order_item_id)
  if order_item_ids.compact.present?
    response = Hashie::Mash.new Bizongo::Communicator.order_items_index!({ids: order_item_ids})
    @order_items = response[:order_items]
  end
  end_time = Time.now

  Rails.logger.info "Execution time for method DispatchPlan::dispatch_plan_item_details - #{(end_time - start_time) * 1000} ms"
  { order_items: @order_items, bizongo_po_items: @bizongo_po_items }
end

def update_dpir_product_details (item_details, dispatch_plan)
  bizongo_po_items = item_details[:bizongo_po_items] if item_details[:bizongo_po_items].present?
  order_items = item_details[:order_items] if item_details[:order_items].present?
  begin
    dispatch_plan.dispatch_plan_item_relations.each do |dpir|
      is_update = false
      product_details = dpir.product_details.with_indifferent_access
      if DispatchPlan::PO_ITEM_DISPATCH_MODE.include?(dispatch_plan.dispatch_mode.to_sym) && bizongo_po_items.present?
        po_item = bizongo_po_items.find{|item| item["id"].to_i == dpir.bizongo_po_item_id}
        if po_item.present?
          product_specs_snapshot = Hashie::Mash.new(po_item["productSpecsSnapshot"].as_json.deep_transform_keys! { |key| key.underscore })
          product_details[:product_name] = product_specs_snapshot.name
          product_details[:product_matrix] = product_specs_snapshot.product_matrices
          product_details[:product_specifications] = product_specs_snapshot
          product_details[:po_item_gst] = po_item["tax"]
          product_details[:price_per_unit] = po_item["pricePerUnit"]
          product_details[:currency] = po_item["purchaseOrder"]["advancePaymentDetails"].present? ? po_item["purchaseOrder"]["advancePaymentDetails"]["currency"] : "INR"
          product_details[:include_tax] = true
          product_details[:hsn_number] = product_specs_snapshot.hsn
          product_details[:sku_code] = product_specs_snapshot.code
          product_details[:sub_sub_category_id] = product_specs_snapshot.category_id
          product_details[:category_hierarchy] = product_specs_snapshot.category_hierarchy
          is_update = true
        end
      end
      if DispatchPlan::ORDER_ITEM_DISPATCH_MODE.include?(dispatch_plan.dispatch_mode.to_sym) && order_items.present?
        order_item = order_items.find{|item| item[:id].to_i == dpir.order_item_id}
        if order_item.present?
          product_details[:product_name] = order_item[:name]
          product_details[:product_matrix] = order_item[:product_matrix]
          product_details[:product_specifications] = order_item[:product_specifications]
          product_details[:order_item_gst] = order_item[:gst_percentage]
          product_details[:order_price_per_unit] = order_item[:price_per_unit]
          product_details[:max_quantity_tolerance] = order_item[:max_quantity_tolerance]
          product_details[:alias_name] = order_item[:alias_name]
          product_details[:currency] = order_item[:currency].presence || "INR"
          product_details[:include_tax] = order_item[:include_tax].presence || true
          product_details[:hsn_number] = order_item[:hsn_number]
          product_details[:sku_code] = order_item[:master_sku_code]
          product_details[:sub_sub_category_id] = order_item[:sub_sub_category_id]
          product_details[:category_hierarchy] = order_item[:category_hierarchy]
          is_update = true
        end
      end
      if dispatch_plan.warehouse_to_warehouse? && dpir.centre_product_id.present?
        if dpir.master_sku_id.present?
          product_details[:currency] = "INR"
          product_details[:include_tax] = true
          product_details[:sku_code] = convert_sku_id_to_sku_code(dpir.master_sku_id)
          is_update = true
        end
      end
      if is_update.true?
        #p "#{product_details[:hsn_number]}"
        dpir.update_columns(product_details: product_details)
      end
      dispatch_plan.reload
      if dispatch_plan.seller_to_buyer? && dispatch_plan.dispatch_plan_item_relations.any?{|dpir| (dpir.product_details['order_price_per_unit'].blank? || dpir.product_details['order_item_gst'].blank?)}
        Airbrake.notify("Order price details are missing for S2B Dispatch Plan!",
                        parameters: { dispatch_plan_id: dispatch_plan.id, centre_product_ids: dispatch_plan.dispatch_plan_item_relations.map(&:centre_product_id),
                                      order_item_ids: dispatch_plan.dispatch_plan_item_relations.map(&:order_item_id) })
      end
    end
  rescue => exception
    Airbrake.notify("#{exception} ,DPIR product details not updated for dp = #{dispatch_plan.id} ")
  end
end

def fix_invoice_data(shipment_data)
  # For Buyer Invoices use:
  #  shipment_data = [[shipment_id1, invoice_id1], [shipment_id2, invoice_id2], [..], ..]

  # For Credit notes use:
  #  shipment_data = [[return_shipment_id1, credit_note_id1], [return_shipment_id2, credit_note_id2], [..], ..]
  counter = 1
  shipment_data.each do |shipment_ref|
    shipment_id = shipment_ref[0]
    invoice_id = shipment_ref[1]
    shipment = Shipment.find(shipment_id)
    next if shipment.nil?

    dispatch_plan = shipment.dispatch_plan
    # invoice_id = shipment.buyer_invoice_id if shipment.buyer_invoice_id.present?

    dispatch_plan.update(origin_address_snapshot: Address.find(dispatch_plan.origin_address.id))
    dispatch_plan.update(destination_address_snapshot: Address.find(dispatch_plan.destination_address.id))

    item_details = dispatch_plan.dispatch_plan_item_details
    dispatch_plan.update_dpir_product_details(item_details)
    dispatch_plan.update_company_snapshot(item_details)

    p "#{counter}. Building origin and destination data for Shipment: #{shipment_id}"

    ship_to_details =
      {
        "name": dispatch_plan.destination_address_snapshot['full_name'],
        "gstin": dispatch_plan.destination_address_snapshot['gstin'],
        "state": dispatch_plan.destination_address_snapshot['state'],
        "mobile": dispatch_plan.destination_address_snapshot['mobile_number'],
        "country": 'India',
        "pincode": dispatch_plan.destination_address_snapshot['pincode'],
        "state_code": dispatch_plan.destination_address_snapshot['gstin_state_code'],
        "company_name": dispatch_plan.destination_address_snapshot['company_name'],
        "street_address": dispatch_plan.destination_address_snapshot['street_address']
      }
    # origin_address = dispatch_plan.origin_address
    dispatch_from_details =
      {
        "name": dispatch_plan.origin_address_snapshot['full_name'],
        "gstin": dispatch_plan.origin_address_snapshot['gstin'],
        "state": dispatch_plan.origin_address_snapshot['state'],
        "mobile": dispatch_plan.origin_address_snapshot['mobile_number'],
        "country": 'India',
        "pincode": dispatch_plan.origin_address_snapshot['pincode'],
        "state_code": dispatch_plan.origin_address_snapshot['gstin_state_code'],
        "company_name": dispatch_plan.origin_address_snapshot['company_name'],
        "street_address": dispatch_plan.origin_address_snapshot['street_address']
      }

    begin
      p '... Fixing data now..'
      FinanceServiceDispatcher::Communicator.update_invoice(invoice_id,
                                                            { skip_update_validation: true,
                                                              dispatch_from_details: dispatch_from_details, ship_to_details: ship_to_details })
      p '... Generating E-Invoice..'
      FinanceServiceDispatcher::Requester.new.post("invoices/#{invoice_id}/generate-e-invoice")
      # p "Generating document.."
      # FinanceServiceDispatcher::Requester.new.put("invoices/#{invoice_id}/generate-invoice")
    rescue StandardError => e
      p "ERROR: Something went wrong with Shipment(#{shipment_id}): #{e}"
    end
    counter += 1
  end
end

def retry_invoice_pdf(shipment_ids)
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    if shipment.present?
      FinanceServiceDispatcher::Requester.new.post("invoices/#{shipment.buyer_invoice_id}/generate-e-invoice")
      p "Retrying for #{shipment.buyer_invoice_no}"
    else
      p "There is no Shipment for this ID: #{shipment_id}"
    end
  end
end
