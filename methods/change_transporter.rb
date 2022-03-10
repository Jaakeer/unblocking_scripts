# input will be shipments = [shipment_id1, shipment_id2, ....]
# then run the below method and then type change_transporter(shipments)
def change_transporter(shipments)
    shipments.each do |shipment_id|
        dp = Shipment.find(shipment_id).dispatch_plan
        dp.transporter_type = "seller"
        dp.save

        p "Transporter type for dispatch Plan #{dp.id} has been changed to #{dp.transporter_type}"

    end
end


