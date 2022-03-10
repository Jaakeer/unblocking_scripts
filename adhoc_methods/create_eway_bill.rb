def create_eway_bill(shipment_id)
  @shipment = Shipment.find_by_id(shipment_id) if shipment_id.present?
  raise ValidationError, "No shipment found for #{shipment_id}." if @shipment.blank?
  @dispatch_plan = @shipment.dispatch_plan
  raise ValidationError, "Dispatch plan not found for shipment" if @dispatch_plan.blank?
  @dispatch_mode = @shipment.dispatch_plan.dispatch_mode
  raise ValidationError, "Dispatch Mode not found " if @dispatch_mode.blank?
  @auto_generated = true
  get_items
  @same_bill_from_ship_from = 1
  @different_bill_from_ship_from = 3
  @transporter_id =
    if @dispatch_plan.seller?
      @shipment.transition_address_id.present? ? @shipment.transition_address.gstin : APP_CONFIG['masters_eway']['gstin_of_consignor']
    else
      @shipment.transporter.gstin
    end
  @gstin_of_consignee = @dispatch_plan.seller? ? "URP" : @dispatch_plan.destination_address.gstin
end

def generate_bill
  token = authenticate
  url = APP_CONFIG['masters_eway']['generate']
  request = generate(token).to_json
  response = Masters::ApiExecutor.post(url, request)
  response = Hashie::Mash.new response
  attach_bill(response)
  response
end

def cancel_bill
  token = authenticate
  bill_no = @shipment.shipment_documents.bizongo_eway_bill.first.try(:document_number)
  raise ValidationError, "Eway bill document number not found." if bill_no.blank?
  response = cancel(token, bill_no)
  response = Hashie::Mash.new response
  if response.results.code == 200
    doc = ShipmentDocument.find_by_document_number(bill_no)
    doc.status = "cancelled"
    doc.save!
    response
  else
    raise ValidationError, "#{response.results.message}"
  end
end

private

def get_items
  case @dispatch_mode.to_sym
  when :seller_to_warehouse, :seller_to_buyer
    bizongo_po_item_ids = @dispatch_plan.dispatch_plan_item_relations.pluck(:bizongo_po_item_id)
    response = Bizongo::Communicator.bizongo_po_items_index!({ ids: bizongo_po_item_ids })
    @items = response[:bizongo_po_items]
  when :warehouse_to_warehouse
    centre_product_ids = @dispatch_plan.dispatch_plan_item_relations.pluck(:centre_product_id)
    tax_response = Hashie::Mash.new(TaxationServiceDispatcher::Communicator.get_product_hsn_and_tax({ "centreProductIds": centre_product_ids.join(',') }))
    @items = tax_response.content
  when :buyer_to_warehouse, :warehouse_to_buyer
    order_item_ids = @dispatch_plan.dispatch_plan_item_relations.pluck(:order_item_id)
    response = Bizongo::Communicator.order_items_index!({ ids: order_item_ids })
    @items = response[:order_items]
  end
end

def attach_bill(response)
  if response.results.code == 200
    bill_no = response.results.message.ewayBillNo
    bill_url = response.results.message.url

    file_name = "eway_bill_#{@shipment.id}.pdf"
    directory = "tmp"

    path = File.join(directory, file_name)

    File.open(path, "wb") do |file|
      file.write open("http://#{bill_url}").read
    end

    attachment = Attachment.new
    attachment.file = File.open(path)
    attachment.save

    @shipment.shipment_documents_attributes = [{ attachment_id: attachment.id, document_type: "bizongo_eway_bill", document_number: bill_no, status: @auto_generated.true? ? "auto_generated" : "generated" }]
    @shipment.save!
  else
    to = ["renuka.singh@bizongo.com"]
    cc_emails = ["shashank@bizongo.com", "ishan.purohit@bizongo.com", "jakir.hassan@bizongo.com", "piyush.shukla@bizongo.com"]
    subject = "Eway bill not generated for shipment - #{@shipment.id} "
    content = response.results.message
    ActivityMailer.send_activity_pending_details(to, cc_emails, subject, content, nil).deliver_now
    raise ValidationError, "#{response.results.message}"
  end
end

def authenticate
  url = APP_CONFIG['masters_eway']['authenticate']
  request = {
    "username": APP_CONFIG['masters_eway']['username'],
    "password": APP_CONFIG['masters_eway']['password'],
    "client_id": APP_CONFIG['masters_eway']['client_id'],
    "client_secret": APP_CONFIG['masters_eway']['client_secret'],
    "grant_type": APP_CONFIG['masters_eway']['grant_type']
  }.to_json
  response = Masters::ApiExecutor.post(url, request)
  if response.key?("access_token")
    response["access_token"]
  else
    raise ValidationError("Authentication failed #{response}")
  end
end

def cancel(token, eway_bill_number)
  url = APP_CONFIG['masters_eway']['cancel']
  request = {
    "access_token": token,
    "userGstin": Rails.env.production? && @shipment.transition_address_id.present? ? @shipment.transition_address.gstin : APP_CONFIG['masters_eway']['userGstin'],
    "eway_bill_number": eway_bill_number,
    "reason_of_cancel": "Others",
    "cancel_remark": "Cancelled the order",
    "data_source": "erp"
  }.to_json
  response = Masters::ApiExecutor.post(url, request)
end

def generate(token)
  {
    "access_token": token,
    "userGstin": Rails.env.production? && @shipment.transition_address_id.present? ? @shipment.transition_address.gstin : APP_CONFIG['masters_eway']['user_gstin'],
    "supply_type": "Outward",
    "sub_supply_type": "Supply",
    "sub_supply_description": "sales to other state",
    "generate_status": 1,
    "data_source": "erp",
    "user_ref": "1232435466sdsf234",
    "location_code": "XYZ",
    "eway_bill_status": "AC",
    "auto_print": "Y",
    "email": "logistics@bizongo.com",
    "itemList": get_item_list
  }.merge(consignor_details).merge(consignee_details).merge(transporter_detail).merge(invoice_details)
end

def get_item_list
  items = []
  @dispatch_plan.dispatch_plan_item_relations.each do |dpir|
    item = {}
    item[:product_name] = dpir.product_details["product_name"]
    item[:product_description] = dpir.product_details["product_name"]
    item[:hsn_code] = get_hsn_number(dpir)
    item[:quantity] = dpir.shipped_quantity
    item[:unit_of_product] = ""
    item[:cgst_rate] = @dispatch_plan.is_igst ? "0" : "#{dpir.get_tentative_tax_percentage / 2}"
    item[:sgst_rate] = @dispatch_plan.is_igst ? "0" : "#{dpir.get_tentative_tax_percentage / 2}"
    item[:igst_rate] = @dispatch_plan.is_igst ? "#{dpir.get_tentative_tax_percentage}" : "0"
    item[:cess_rate] = "0"
    item[:cessNonAdvol] = "0"
    item[:taxable_amount] = dpir.total_buyer_amount_without_tax
    items << item
  end
  items
end

def consignor_details
  {
    "gstin_of_consignor": Rails.env.production? && @shipment.transition_address_id.present? ? @shipment.transition_address.gstin : APP_CONFIG['masters_eway']['gstin_of_consignor'],
    "legal_name_of_consignor": @shipment.transition_address.full_name,
    "address1_of_consignor": @dispatch_plan.origin_address.full_name,
    "address2_of_consignor": @dispatch_plan.origin_address.street_address,
    "place_of_consignor": @dispatch_plan.origin_address.city,
    "pincode_of_consignor": @dispatch_plan.origin_address.pincode,
    "state_of_consignor": @shipment.transition_address.state,
    "actual_from_state_name": @dispatch_plan.origin_address.state
  }
end

def consignee_details
  {
    "gstin_of_consignee": @gstin_of_consignee,
    "legal_name_of_consignee": @dispatch_plan.destination_address.full_name,
    "address1_of_consignee": @dispatch_plan.destination_address.full_name,
    "address2_of_consignee": @dispatch_plan.destination_address.street_address,
    "place_of_consignee": @dispatch_plan.destination_address.city,
    "pincode_of_consignee": @dispatch_plan.destination_address.pincode,
    "state_of_supply": @dispatch_plan.destination_address.state,
    "actual_to_state_name": @dispatch_plan.destination_address.state

  }
end

def invoice_details
  total_amount = @shipment.dispatch_plan_item_relations.by_non_zero_shipped_quantity.sum(&:total_buyer_amount_without_tax)
  total_tax = @shipment.dispatch_plan_item_relations.sum(&:tax_amount)
  {
    "document_type": "Tax Invoice",
    "document_number": @shipment.invoice.present? && @shipment.invoice.dc? ? @shipment.buyer_delivery_challan_no : @shipment.buyer_invoice_no,
    "document_date": DateTime.now.strftime("%d/%m/%Y"),
    "other_value": 0,
    "total_invoice_value": total_amount + total_tax,
    "taxable_amount": total_amount,
    "cgst_amount": @dispatch_plan.is_igst ? 0 : total_tax / 2,
    "sgst_amount": @dispatch_plan.is_igst ? 0 : total_tax / 2,
    "igst_amount": @dispatch_plan.is_igst ? total_tax : 0,
    "cess_amount": 0,
    "cess_nonadvol_value": 0
  }
end

def transporter_detail
  {
    "transaction_type": @shipment.transition_address.gstin == @dispatch_plan.origin_address.gstin ? @same_bill_from_ship_from : @different_bill_from_ship_from,
    "transporter_id": @transporter_id,
    "transporter_name": @shipment.transporter.present? ? @shipment.transporter.name : "",
    "transporter_document_number": "",
    "transporter_document_date": "",
    "transportation_mode": "",
    "transportation_distance": "",
    "vehicle_number": "",
    "vehicle_type": ""
  }
end

def get_hsn_number(dpir)
  hsn_number = nil
  case @dispatch_mode.to_sym
  when :seller_to_warehouse, :seller_to_buyer
    hsn_number = @items.select { |item| item[:id] == dpir.bizongo_po_item_id }.first[:hsn_number]
  when :warehouse_to_warehouse
    hsn_number = @items.select { |item| item[:id] == dpir.centre_product_id }.first[:hsn_number]
  when :buyer_to_warehouse, :warehouse_to_buyer
    hsn_number = @items.select { |item| item[:id] == dpir.order_item_id }.first[:hsn_number]
  end
  raise ValidationError, "Invalid hsn number for given sku" unless hsn_number.present?
  hsn_number
end
