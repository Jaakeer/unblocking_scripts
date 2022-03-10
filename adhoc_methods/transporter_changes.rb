def change_transporter(dp_ids, type)
  if type == "b2b"
    transporter = Transporter.find(31)
  elsif type == "b2c"
    transporter = Transporter.find(494)
  end
  counter = 1
  dp_ids.each do |dp_id|
    dispatch_plan = DispatchPlan.find(dp_id)
    p "#{counter}. Starting with Dispatch Plan #{dp_id}"
    dispatch_plan.suggested_transporter_id = transporter.id
    dispatch_plan.suggested_transporter_name = transporter.clickpost_account_code
    dispatch_plan.save
    shipment = dispatch_plan.shipment

    if shipment.present?
      shipment.transporter_id = transporter.id
      shipment.save(validate: false)
      if shipment.packaging_labels.present?
        shipment.packaging_labels.each do |pl|
          pl.delete
          p "Old Packaging Labels deleted.."
        end
      end
      CreateOrderToClickpostJob.perform_later(shipment.id)
      p "Refetching Labels.."
    end
    counter = counter + 1
  end
end
