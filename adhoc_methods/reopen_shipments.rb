def rollback_invoices(shipment_id)
  s = Shipment.find(shipment_id)
  s.status = :ready_to_ship
  s.save(validate: false)
  update_params = {}
  update_params.merge!({ status: "PENDING_REVIEW" })
  response = FinanceServiceDispatcher::Communicator.update_invoice(s.seller_invoice_id, update_params) if s.seller_invoice_id.present?
  p "#{response}" if !response.blank?
  response = FinanceServiceDispatcher::Communicator.update_invoice(s.buyer_invoice_id, update_params) if s.buyer_invoice_id.present?
  p "#{response}" if !response.blank?
end