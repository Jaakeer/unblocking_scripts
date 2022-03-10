#input = [[shipment_id1, "due_date1"], [shipment_id2, "due_date2"],....]

def change_due_date(data)
    data.each do |input|
        shipment = Shipment.find(input[0])
        due_date = input[1]
        if shipment.settled == true
            p "Shipment, #{shipment.id} is already settled"
            next
        else
            shipment.seller_due_date = due_date
            shipment.save!
        end
    end
end
