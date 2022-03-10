# LeadPlus Backend
def create_account(company_name)
  Account.create(company_name: company_name, brand_name: company_name, company_type: "large", monthly_packaging_spend: 100000, business_industry_reference_id: 202, generic_source_id: 12, status: "active", account_manager_id: 34308, country: "Thailand")
  return Account.where(company_name: company_name).first.id
end

def create_poc(name, email, contact_number, account_id)
  PointOfContact.create(name: name, email: email, contact_number: contact_number, account_id: account_id, authority: "commercial_buyer", primary: true, landline_number: contact_number, mobile_number_country_details: {"countryCode"=>"66", "countrySortName"=>"th"}, landline_number_country_details: {"countryCode"=>"66", "countrySortName"=>"th"})
  return PointOfContact.where(name: name).first
end

# Bizongo Backend
def create_buyer_company(name)

end


