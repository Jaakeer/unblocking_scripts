# frozen_string_literal: true

def fill_line_items(invoice_data)
  counter = 1
  invoice_data.each do |ref|
    invoice_id = ref[0]
    shipment_id = ref[1]
    shipment = Shipment.find(shipment_id)
    amount = 0
    shipment.dispatch_plan_item_relations.each do |line_item|
      returned_quantity = 3000
      fulfillment_charges = line_item.buyer_service_charge.to_f
      fulfillment_charges_tax = line_item.buyer_service_charge_tax.to_f
      amount += fulfillment_charges + fulfillment_charges_tax + (returned_quantity.to_f * line_item.product_details['order_price_per_unit'].to_f * (1 + (line_item.product_details['order_item_gst'].to_f * 0.01))).to_f.floor(2)
    end
    p "#{counter}. Starting with shipment #{shipment.id}"
    line_item_details = return_line_item(shipment)
    p '....Fixing line item on the CN'
    FinanceServiceDispatcher::Communicator.update_invoice(invoice_id,
                                                          { skip_update_validation: true,
                                                            line_item_details: line_item_details, amount:amount })

    p '....Retrying IRN'
    FinanceServiceDispatcher::Requester.new.post("invoices/#{invoice_id}/generate-e-invoice")
    counter += 1
  end
end

def return_line_item(shipment)
  amount = 0
  line_item_details = []
  shipment.dispatch_plan_item_relations.each do |line_item|
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
  line_item_details
end

