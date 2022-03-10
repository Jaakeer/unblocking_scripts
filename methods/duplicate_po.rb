def create_invoice(dp_ids)
  dp_ids.each do |dp_id|
    dp = DispatchPlan.find(dp_id)
    create_invoice = InvoiceServices::Create.new(create_invoice_params(dp))
    create_invoice.execute
    if create_invoice.errors.present?
      p "#{create_invoice.errors}"
    else
      @invoice = create_invoice.result
    end
  end
end

def create_invoice_params(dispatch_plan)
  @dispatch_plan = dispatch_plan
  @shipment = dispatch_plan.shipment
  {
      dispatch_plan_attributes: {
          id: @dispatch_plan.id
      },
      shipment_attributes: @shipment
  }
end