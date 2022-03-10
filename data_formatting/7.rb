# frozen_string_literal: true

def skip_qc(dp_ids)
  DispatchPlan.where(id: dp_ids).each do |dp|
    next if dp.dispatch_mode == 1

    begin
      dp.quality_check_status = 3
      dp.save(validate: false)
      timeline = dp.timelines.where(timeline_type: 'quality').first
      timeline.qc_skippable = true
      timeline.save(validate: false)
    rescue StandardError => e
      p e.to_s
    end
  end.nil?
end

def rerun_dp_automation(delivery_groups)
  DeliveryGroup.where(pretty_id: delivery_groups).each do |dg|
    next unless dg.direct_orders.present?

    begin
      dg.direct_orders.each do |dor|
        p "Running for #{dor.id}"
        CreateCheckpointForDirectOrderWorker.new.perform(dor.id, source: 'rake')
      end
    rescue StandardError => e
      p e.to_s
    end
  end.nil?
end

emails.each do |email|
  a = User.where(email: email).first
  a.password = 'Ansapack@123'
  a.password_confirmation = a.password
  a.save!
end
