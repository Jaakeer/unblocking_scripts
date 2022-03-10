# input data >> shipments = [shipment_id1, shipment_id2...]

#Run this in WEB1 first
def remove_settlement(shipments)
    shipments.each do |id|
        if BizongoPurchaseOrdersSettlementsRelation.where(shipment_id: id).present?
            bposr_id = BizongoPurchaseOrdersSettlementsRelation.where(shipment_id: id).sort.last.id
            BizongoPurchaseOrdersSettlementsRelation.delete(bposr_id)
            p "Settlement relation record deleted\n"
        else
            p "Settlement relation do not exist for #{id}, deleting settlement record for the shipment now"
        end
    end
end


#Run this in SC!
def remove_settlement(shipments)
    shipments.each do |id|
        shipment = Shipment.find(id)
        shipment.total_paid_to_seller = 0
        shipment.settled = false
        shipment.settled_at = nil
        shipment.seller_payment_status = 'pending'
        shipment.review_status = 'pending_review'
        shipment.save
        puts "Shipment: #{id} settlement status has been rolled back successfully"
    end
end

def rollback_settlement(settlement_id)
    FinanceServiceDispatcher::Requester.new.put("payments/#{settlement_id}/rollback")
end


