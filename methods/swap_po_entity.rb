# This is main method to be run with final data
# po_data = [[<current_po_no>, <cancelled_po_no>], [<current_po_no>, <cancelled_po_no>], ... ]
def swap_po_entity(po_data)
  po_data.uniq.each do |data|
    current_po_no = data[0]
    cancelled_po_no = data[1]
    if validate(cancelled_po_no)
      swapped = swap_entity(current_po_no, cancelled_po_no)
      regenerate_po_files(data) if swapped
    end
  end
end

def swap_entity(current_po_no, cancelled_po_no)
  cancelled_po_data = create_po_data(cancelled_po_no)
  current_po_data = create_po_data(current_po_no)
  if cancelled_po_data.present? && current_po_data.present?
    begin
      set_blank(cancelled_po_no)
      current = assign_po_attributes(current_po_data[:po_id], cancelled_po_data)
      cancelled = assign_po_attributes(cancelled_po_data[:po_id], current_po_data) if current
      if cancelled
        p "Entity swapped successfully for #{current_po_no} to #{cancelled_po_no}"
        advance_settled = fix_advance_settlement(current_po_data[:po_id], cancelled_po_data[:po_number])
        return advance_settled
      else
        return false
      end
    rescue => e
      p "Something went wrong while swapping po attributes for #{current_po_no} due to #{e}"
      p "Fixing the cancelled po data"
      revert_po_no(cancelled_po_data[:po_id], cancelled_po_no)
      return false
    end
  else
    p "Couldn't create PO Data, please review the requirements #{current_po_no}"
    return false
  end
end

def validate(cancelled_po_no)
  cancelled_po = BizongoPurchaseOrder.where(po_number: cancelled_po_no).first
  if cancelled_po.blank?
    p "Cancelled PO was not found, please check po number: #{cancelled_po_no}"
    return false
  elsif cancelled_po.status != "cancelled"
    p "PO provided is not cancelled, cannot use this po: #{cancelled_po_no}"
    return false
  elsif AdvanceSettlement.where(bizongo_purchase_order_id: cancelled_po.id).present?
    p "There is an advance payment against provided cancelled PO: #{cancelled_po_no}, cannot proceed"
    return false
  else
    return true
  end
end

def assign_po_attributes(po_id, po_data)
  po = BizongoPurchaseOrder.find(po_id)
  return false if po.nil?
  po.po_number = po_data[:po_number]
  po.buyer_id = po_data[:buyer_id]
  po.buyer_address_id = po_data[:buyer_address_id]
  po.buyer_address = po_data[:buyer_address]
  po.buyer_gstin = po_data[:buyer_gstin]
  po.buyer_name = po_data[:buyer_name]
  po.created_at = po_data[:created_at]
  saved = po.save(validate: false)
  return saved
end

def create_po_data(po_no)
  po_data = Hash.new
  po = BizongoPurchaseOrder.where(po_number: po_no).first
  return po_data if po.nil?
  po_data[:po_id] = po.id
  po_data[:po_number] = po.po_number
  po_data[:buyer_id] = po.buyer_id
  po_data[:buyer_address_id] = po.buyer_address_id
  po_data[:buyer_address] = po.buyer_address
  po_data[:buyer_gstin] = po.buyer_gstin
  po_data[:buyer_name] = po.buyer_name
  po_data[:created_at] = po.created_at
  return po_data
end

def regenerate_po_files(data)
  data.each do |po_no|
    po_id = BizongoPurchaseOrder.where(po_number: po_no).first.id
    PoFileGenerateWorker.perform_now(po_id)
  end
end

def fix_advance_settlement(po_id, po_number)
  if AdvanceSettlement.where(bizongo_purchase_order_id: po_id).present?
    AdvanceSettlement.where(bizongo_purchase_order_id: po_id).each do |advance|
      advance.po_number = po_number
      return advance.save(validate: false)
    end
  else
    return true
  end
end

#This is to get rid of po number on cancelled po (Temporarily) to avoid unique constraint issues in DB
def set_blank(cancelled_po_no)
  cancelled_po = BizongoPurchaseOrder.where(po_number: cancelled_po_no).first
  if cancelled_po.present?
    cancelled_po.po_number = nil
    cancelled_po.save(validate: false)
  end
end

#This is to revert the po number on cancelled po, in case the swapping is unsuccessful
def revert_po_no(po_id, cancelled_po_no)
  po = BizongoPurchaseOrder.find(po_id)
  po.po_number = cancelled_po_no
  po.save(validate: false)
end