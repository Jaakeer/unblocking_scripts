# frozen_string_literal: true

def fix_data(return_shipment_ids)
  counter = 1
  Shipment.where(id: return_shipment_ids).each do |return_shipment|
    forward_shipment = return_shipment.forward_shipment
    p "#{counter}. Changing Forward shipment status for shipment: #{forward_shipment.id}"
    forward_shipment.status = 'returned'
    forward_shipment.save(validate: false)
    # FinanceServiceDispatcher::Communicator.update_invoice(forward_shipment.buyer_invoice_id,{ skip_update_validation: true,status: "PENDING_REVIEW"})
    return_shipment.dispatch_plan_item_relations.each do |dpir|
      p "    DPIR ID: #{dpir.id}"
      if dpir.returned_quantity.zero?
        p '    Found 0 returned qty'
        dpir.lost_quantity = dpir.quantity
        p "Changed lost qty to #{dpir.quantity}"
        dpir.save(validate: false)
      end
    end
    p "    Added some lost data to return shipment: #{return_shipment.id}"
    FinanceServiceDispatcher::Communicator.create_invoice(get_lost_data(return_shipment))
    p '    A new CN should be created now..'
    counter += 1
  end.nil?
end

def get_lost_data(lost_shipment)
  response = FinanceServiceDispatcher::Communicator.show_invoice(lost_shipment.forward_shipment.buyer_invoice_id)
  comment = 'Nullification of incorrect returns or cancellations'

  amount = 0
  line_item_details = []
  lost_shipment.dispatch_plan_item_relations.each do |line_item|
    next if line_item.lost_quantity == 0
    amount += (line_item.lost_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f * (1 + (line_item.product_details['order_item_gst'].to_f * 0.01))).to_f.floor(2)
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
