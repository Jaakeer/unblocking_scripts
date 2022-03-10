def create_tracking_data(shipment_id)
  shipment = Shipment.find(shipment_id)
  request_params = {
    waybill: shipment.tracking_id,
    cp_id: shipment.transporter.clickpost_account_code
  }
  result = Hashie::Mash.new(request_params)
  result
end

task add_tracking_details_to_shipment: :environment do
  dispatch_modes = ["seller_to_buyer", "warehouse_to_buyer", "warehouse_to_seller", "buyer_to_seller", "buyer_to_warehouse"]
  shipments = Shipment.by_dispatch_plan_modes(dispatch_modes).dispatched.clickpost_shipments.where("tracking_id IS NOT NULL")
  shipments.each do |shipment|
    add_tracking_details(shipment)
  end
end