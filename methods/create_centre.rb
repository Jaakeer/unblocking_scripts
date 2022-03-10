def create_centre(purchase_orders)
    for i in purchase_orders do
    company = Company.find(i)
    current_user = company.users.first
    hq_centre_creation_context = Hash.new
    hq_centre_creation_context[:company_id] = company.id
    hq_centre_creation_context[:name] = "#{company.name} HQ"
    hq_centre_creation_context[:is_hq] = true
    hq_centre_creation_context[:requester] = current_user
    hq_centre_creation_context[:anonymous_hq_creator] = true
    new_centre_service = Centre::CreateCentre.new(hq_centre_creation_context)
    new_centre_service.execute
    end
end