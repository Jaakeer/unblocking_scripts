dp_ids.each do |dp_id|
  dp = DispatchPlan.find(dp_id)
  dpir = dp.dispatch_plan_item_relations.first
  dpir.lot_informations.where(inward: true, is_valid: true).each do |li|
    qty = li.quantity
    if li.lot_information_locations.sum(&:quantity) != qty
      lil = li.lot_information_locations.first
      remaining = qty - lil.quantity
      lil.quantity = qty
      lil.remaining_quantity = lil.remaining_quantity + remaining
      lil.save!
    end
  end
end

counter = 0
Shipment.where(dispatch_plan_id: dp_ids).each do |shipment|
  counter = counter + 1
  if !shipment.packaging_labels.present?
    shipment.update(no_of_packages: 1) if !shipment.no_of_packages.nil?
    rerun_recommendation([shipment.dispatch_plan_id]) if !shipment.transporter_id.present?
    if shipment.dispatch_plan.suggested_transporter_id.present? || shipment.transporter_id.present?
      shipment.transporter_id = shipment.dispatch_plan.suggested_transporter_id if shipment.transporter_id.nil?
      shipment.save
      CreateOrderToClickpostJob.perform_later(shipment.id)
      p "#{counter}. Clickpost call made for #{shipment.id}"
    elsif !shipment.dispatch_plan.suggested_transporter_id.present?
      p "#{counter}. No recommendation present for #{shipment.id}"
    else
      p "#{counter}. Doesn't satisfy any conditions"
    end
  else
    p "#{counter}. Label already present for #{shipment.id}"
  end
end.nil?


dp_data = []
Shipment.where(dispatch_plan_id: dp_ids).each do |shipment|
  if !shipment.dispatch_plan.suggested_transporter_id.present?
    dp_data.push(shipment.dispatch_plan_id)
  end
end.nil?
dp_data

sum = 0
dp_data = []
Shipment.where(dispatch_plan_id: dp_ids).each do |shipment|
  if shipment.packaging_labels.present?
    sum = sum + 1
  else
    dp_data.push(shipment.dispatch_plan_id)
  end
end.nil?
p sum
dp_data

dp_data = []
Shipment.where(dispatch_plan_id: dp_ids).each do |shipment|
  if shipment.buyer_invoice_no.nil?
    dp_data.push(shipment.dispatch_plan_id)
  end
end.nil?
dp_data