def fetch_pod(shipment_ids)
  counter = 0
  shipment_ids.each do |shipment_id|
    shipment = Shipment.find(shipment_id)
    counter += 1
    next if shipment.blank? || shipment.status != 'delivered'

    start_time = Time.now
    p "#{counter}. ------------ Starting with Shipment ID: #{shipment_id} ------------"
    if !shipment.transporter.clickpost_cp_id.nil? && !shipment.buyer_pod_file.present?
      update_pod_for_shipment(shipment)
      s = Shipment.find(shipment_id)
      end_time = Time.now
      if s.buyer_pod_file.present?
        p "SUCCESS: POD file fetched for shipment successfully [Execution Time: #{(end_time - start_time) * 1000} ms]"
      end
    elsif shipment.transporter.clickpost_cp_id.nil?
      p 'ERROR: No Clickpost account assigned to the shipment'
    elsif shipment.buyer_pod_file.present?
      p 'SUCCESS: POD already present for the shipment'
    end
  end
end

def update_pod_for_shipment(shipment)
  begin
    request = {
      waybill: shipment.tracking_id.strip,
      cp_id: shipment.transporter.clickpost_cp_id
    }
    p 'Fetching the POD from clickpost..'
    response = Hashie::Mash.new(LogisticsDispatcher::Communicator.shipment_pod_details(request))

    if response.errors.present?
      p "ERROR: Fetching POD details from Clickpost Failed because of #{response.errors}"
    else
      if response.result.present? && response.result.pod_url.present?
        pod_url = response.result.pod_url
        shipment.remote_buyer_pod_file_url = pod_url
        shipment.pod_uploaded_at = Time.now
        shipment.pod_updated_at = Time.now
        shipment.automatic_buyer_pod_uploaded = true

        shipment.save(validate: false)
      else
        p 'ERROR: No POD URL sent by clickpost..'
      end
    end
  rescue => e
    p "ERROR: POD details from Clickpost Failed because of #{e}"
  end
end