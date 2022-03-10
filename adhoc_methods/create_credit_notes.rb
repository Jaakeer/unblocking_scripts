# frozen_string_literal: true

# @param [Object] shipment_ids
# @return [Object] recon_data
def create_credit_note(shipment_ids)
  counter = 1
  recon_data = []
  Shipment.where(id: shipment_ids).each do |shipment|
    # next if shipment.status == "cancelled"
    dispatch_plan = shipment.dispatch_plan
    p "#{counter}. Starting with #{shipment.id} (#{shipment.buyer_invoice_no}), Mode: #{shipment.dispatch_plan.dispatch_mode}"
    begin
      case dispatch_plan.dispatch_mode
      when 'warehouse_to_buyer', 'seller_to_buyer'
        if shipment.cancelled?
          p '__ Shipment is cancelled. Trying to generate CN'
          FinanceServiceDispatcher::Communicator.create_invoice(get_cancelled_data(shipment))
        elsif shipment.status == 'shipment_lost' || shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum.positive?
          p '__ Found some lost quantity, Trying to generate CN'
          FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(shipment))
        elsif shipment.return_shipments.present?
          p '__ Found return shipment(s)'
          shipment.return_shipments.each do |return_shipment|
            next if return_shipment.cancelled?

            p "___ Trying to generate CN for #{return_shipment.id}"
            if return_shipment.shipment_lost?
              FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(return_shipment))
            else
              FinanceServiceDispatcher::Communicator.create_invoice(get_return_data(return_shipment))
              if return_shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum.positive?
                FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(return_shipment))
              end
            end
          end
        end

      when 'buyer_to_warehouse', 'buyer_to_seller'
        FinanceServiceDispatcher::Communicator.create_invoice(get_return_data(shipment))
        p '__ Trying to generate CN for return. Will check for lost data next.'
        if shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum.positive?
          FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(shipment))
        end
      else
        p "ERROR: Invalid dispatch mode, please check Shipment #{shipment.id}"
      end
      counter += 1
    rescue StandardError => e
      p "ERROR: Something broke #{e}"
      recon_data.push(shipment.id)
    end
  end.nil?
  recon_data
end

# @param [Object] credit_note_no
# @param [Object] shipment_id
def cancel_credit_note(shipment_id, credit_note_no)
  shipment = Shipment.find(shipment_id)
  credit_notes = FinanceServiceDispatcher::Communicator.index_notes(shipment.buyer_invoice_id,
                                                                    { invoice_number: credit_note_no })
  credit_note = credit_notes['notes'].first
  credit_note['status'] = 'CANCELLED'
  begin
    FinanceServiceDispatcher::Requester.new.post("invoices/#{credit_note['id']}/cancel-e-invoice")
    # FinanceServiceDispatcher::Communicator.update_invoice(credit_note["id"],credit_note)
  rescue StandardError => e
    p "Something went wrong: #{e}"
  end
end

# @param [Object] return_shipment
# @return [Hash{Symbol->String | Integer}]
def get_return_data(return_shipment)
  response = FinanceServiceDispatcher::Communicator.show_invoice(return_shipment.forward_shipment.buyer_invoice_id)
  comment = 'Return for combo SKU'
  amount = 0
  line_item_details = []
  return_shipment.dispatch_plan_item_relations.each do |line_item|
    returned_quantity = line_item.shipped_quantity # This is required to handle cases of partially lost quantity in a return shipment
    next if returned_quantity.zero?
    fulfillment_charges = line_item.buyer_service_charge.to_f
    fulfillment_charges_tax = line_item.buyer_service_charge_tax.to_f
    amount += fulfillment_charges + fulfillment_charges_tax + (returned_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f * (1 + (line_item.product_details['order_item_gst'].to_f * 0.01))).to_f.floor(2)
    line_item_details << {
      dispatch_plan_item_relation_id: line_item.id,
      hsn: line_item.product_details['hsn_number'],
      quantity: returned_quantity.to_f,
      amount_without_tax: (returned_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f).to_f.floor(2),
      tax_percentage: line_item.product_details['order_item_gst'].to_f,
      item_name: line_item.product_details['alias_name'].present? ? line_item.product_details['alias_name'] : line_item.product_details['product_name'],
      price_per_unit: line_item.product_details['order_price_per_unit']
    }
  end
  {
    invoice_date: DateTime.now.strftime('%Y-%m-%d'),
    type: 'CREDIT_NOTE',
    invoice_id_for_note: response[:id],
    entity_reference_number: response[:entity_reference_number],
    amount: amount,
    file: '',
    line_item_details: line_item_details,
    supplier_details: response[:supplier_details],
    buyer_details: response[:buyer_details],
    ship_to_details: response[:ship_to_details],
    dispatch_from_details: response[:dispatch_from_details],
    supporting_document_details: {
      invoice_using_igst: response[:supporting_document_details][:invoice_using_igst],
      comment: comment
    },
    centre_reference_id: response[:center_reference_id],
    pan: response[:pan],
    shipment_id: return_shipment.id,
    account_type: 'BUYER'
  }
end

# @param [Object] shipment
def get_cancelled_data(shipment)
  response = FinanceServiceDispatcher::Communicator.show_invoice(shipment.buyer_invoice_id)
  credit_note_data = {
    invoice_date: DateTime.now.strftime('%Y-%m-%d'),
    type: 'CREDIT_NOTE',
    sub_type: 'INVOICE_NULLIFICATION',
    invoice_id_for_note: response[:id],
    entity_reference_number: response[:entity_reference_number],
    amount: shipment.total_buyer_invoice_amount,
    delivery_amount: response[:delivery_amount],
    file: '',
    line_item_details: response[:line_item_details],
    supplier_details: response[:supplier_details],
    buyer_details: response[:buyer_details],
    ship_to_details: response[:ship_to_details],
    dispatch_from_details: response[:dispatch_from_details],
    supporting_document_details: {
      invoice_using_igst: response[:supporting_document_details][:invoice_using_igst],
      comment: 'Wrong Invoice'
    },
    centre_reference_id: response[:center_reference_id],
    pan: response[:pan],
    shipment_id: response[:shipment_id],
    account_type: 'BUYER'
  }
end

# @param [Object] lost_shipment
def get_lost_data(lost_shipment)
  response = FinanceServiceDispatcher::Communicator.show_invoice(lost_shipment.forward_shipment.buyer_invoice_id)
  comment = 'Nullification of incorrect returns'

  amount = 0
  line_item_details = []
  lost_shipment.dispatch_plan_item_relations.each do |line_item|
    next if line_item.lost_quantity.zero?

    fulfillment_charges = dpir.buyer_service_charge.to_f
    fulfillment_charges_tax = dpir.buyer_service_charge_tax.to_f
    amount += fulfillment_charges + fulfillment_charges_tax + (returned_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f * (1 + (line_item.product_details['order_item_gst'].to_f * 0.01))).to_f.floor(2)
    line_item_details << {
      dispatch_plan_item_relation_id: line_item.id,
      hsn: line_item.product_details['hsn_number'],
      quantity: line_item.lost_quantity.to_f,
      amount_without_tax: (line_item.lost_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f).to_f.floor(2),
      tax_percentage: line_item.product_details['order_item_gst'].to_f,
      item_name: line_item.product_details['alias_name'].present? ? line_item.product_details['alias_name'] : line_item.product_details['product_name'],
      price_per_unit: line_item.product_details['order_price_per_unit']
    }
  end
  {
    invoice_date: DateTime.now.strftime('%Y-%m-%d'),
    type: 'CREDIT_NOTE',
    invoice_id_for_note: response[:id],
    entity_reference_number: response[:entity_reference_number],
    amount: amount,
    file: '',
    line_item_details: line_item_details,
    supplier_details: response[:supplier_details],
    buyer_details: response[:buyer_details],
    ship_to_details: response[:ship_to_details],
    dispatch_from_details: response[:dispatch_from_details],
    supporting_document_details: {
      invoice_using_igst: response[:supporting_document_details][:invoice_using_igst],
      comment: comment
    },
    centre_reference_id: response[:center_reference_id],
    pan: response[:pan],
    shipment_id: lost_shipment.id,
    account_type: 'BUYER'
  }
end

def create_credit_notes_for_returns(shipment_ids)
  counter = 1
  Shipment.where(id: shipment_ids).each do |shipment|
    p "#{counter}. Starting with shipment: #{shipment.id}"
    case shipment.status
    when 'shipment_lost'
      p "....Shipment is marked as #{shipment.status}, creating lost CN"
      FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(shipment))
    when 'delivered'
      p '....Shipment is returned and delivered, creating CN for returned qty'
      FinanceServiceDispatcher::Communicator.create_invoice(get_return_data(shipment))
      if shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum.positive? && shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum < shipment.dispatch_plan_item_relations.map(&:shipped_quantity).sum
        p '......Shipment is also partially lost, creating CN for partial lost qty'
        FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(shipment))
      elsif shipment.dispatch_plan_item_relations.map(&:lost_quantity).sum.positive?
        p ".....NOTE: Shipment #{shipment.id} has same qty in lost and shipped, which is hella weird"
      end
    end
    counter += 1
  end.nil?
end


