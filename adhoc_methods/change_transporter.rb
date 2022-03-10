def change_transporter(dp_ids, transporter_id)
  t = Transporter.find(transporter_id)
  dp_ids.each do |dp_id|
    dp = DispatchPlan.find(dp_id)
    if dp.shipment.blank?
      dp.suggested_transporter_id = t.id
      dp.suggested_transporter_name = t.name
      dp.save(validate: false)
      p "Changed the suggested transporter to #{t.name} on dispatch plan #{dp_id}"
    end
  end
end
