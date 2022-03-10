def create_settlement(shipment_id)
    shipment = Shipment.find(shipment_id)
    supplier_id = shipment.supplier_id

    total_invoice_amount = shipment.total_seller_invoice_amount
    amount_paid_to_seller = shipment.total_paid_to_seller
    total_seller_extra_charges = shipment.seller_extra_charges

    amount_to_be_settled = total_invoice_amount + total_seller_extra_charges - amount_paid_to_seller

    supplier_info = {
        supplier_id: supplier_id,
        amount_to_be_settled: amount_to_be_settled,
        unsettled_shipments: [shipment]
        }

    service = ShipmentServices::SettleShipmentsOnDueDate.new(supplier_info)
    if service.errors.present?
        p service.errors
    elsif service.execute!
        p "Settlement created Shipment: #{shipment_id}, amount: #{amount_to_be_settled}"
    else
        p "Settlement couldn't be created"
    end
end






