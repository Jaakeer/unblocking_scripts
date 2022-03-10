def fix_lost_shipments(invoices)
  invoices.each do |invoice|
    shipment = Shipment.where(buyer_invoice_no: invoice).first
    shipment.dispatch_plan_item_relations.each do |dpir|
      next if dpir.lost_quantity > 0
      if dpir.old_shipped_quantity > 0
        dpir.lost_quantity = dpir.old_shipped_quantity
      else
        dpir.lost_quantity = dpir.shipped_quantity
      end
      dpir.save
    end
  end
end

def requests_params(shipment)
  shipment_params = {
      shipment_id: shipment.id,
      amount: shipment.total_buyer_invoice_amount,
      invoice_number: shipment.buyer_invoice_no,
      remaining_amount: shipment.total_buyer_invoice_amount
  }
  return {shipment: shipment_params}
end

begin
  service = CreditNote::CreateService.new(requests_params(shipment))
  service.execute!
rescue => e
  p "#{e}"
end

def find(po)
  po_data = Hash.new
  po.each do |po_id|
    sum = 0
    DispatchPlan.where(bizongo_purchase_order_id: po_id).each do |dp|
      next if dp.status != "cancelled"
      sum += dp.dispatch_plan_item_relations.map(&:hanging_quantity).sum
    end
    po_data[po_id] = sum if sum > 0
  end
  return po_data
end