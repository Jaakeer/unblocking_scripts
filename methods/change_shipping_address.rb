# format for the data = ([shipment_id/dispatch_plan_id, destination_address_id], 1 Shipment IDs or clickpost_sample.json for Dispatch Plan IDs)


def change_shipping_address(data, type)
    dispatch_plan_invoices = []
        data.each do |s|
            address_id = s[1]
            if type == 1
            shipment_id = s[0]
            dispatch_plan = Shipment.find(shipment_id).dispatch_plan
            elsif type == 2
            dispatch_plan_id = s[0]
            dispatch_plan = DispatchPlan.find(dispatch_plan_id)
            else
                puts "There was a problem with data type, type 1 if data is Shipment IDs and type clickpost_sample.json if data is Dispatch Plan IDs"
            end
            dispatch_plan.destination_address_id = address_id
            status = dispatch_plan.save(validate: false)
                if status
                    dispatch_plan_invoices.push(dispatch_plan.id)
                else
                    puts "There was an issue with changing the address"
                end
        end

    UpdateDpPriceJob.perform_now(dispatch_plan_invoices, true)
end
