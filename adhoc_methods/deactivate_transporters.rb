def deactivate_transporters(transporter_ids)
  counter = 1
  transporter_ids.each do |transporter_id|
    transporter = Transporter.unscoped.where(id: transporter_id).first
    if transporter.active == false
      p "#{counter}. Transporter: #{transporter.name} (#{transporter.id}) is already deactivated"
    else
      begin
        if transporter.clickpost_cp_id.nil?
          transporter.active = false
          transporter.save!
          p "#{counter}. Transporter: #{transporter.name} (#{transporter.id}) has been deactivated"
        else
          p "#{counter}. Transporter: #{transporter.name} (#{transporter.id}) has a ClickPost ID, cannot be deactivated"
        end
      rescue => e
        p "#{counter}. Transporter: #{transporter.name} (#{transporter.id}) has a ClickPost ID, cannot be deactivated due to #{e}"
      end
    end
    counter = counter + 1
  end
end

request = {
  waybill: ['315915995527054'],
  cp_id: 112
}
@response = Hashie::Mash.new(LogisticsDispatcher::Communicator.track_shipment(request_params))

Transporter deactivation