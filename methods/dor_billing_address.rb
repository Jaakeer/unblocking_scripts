def billing_fix(c)
c.each do |id|
  dor = DirectOrder.find(id)
  if dor.direct_order_billing_address.blank?
    bill_id = dor.purchase_order.purchase_order_bulk_attribute.billing_address_id
    next if bill_id.blank?
    f =  DirectOrderBillingAddress.new
    f.direct_order_id = dor.id
    f.billing_address_id = bill_id
    f.save!
  end
end
end