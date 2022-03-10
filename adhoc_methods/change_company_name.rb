def change_company_name(dispatch_plan_ids)
  dp_data = Hash.new
  dispatch_plan_ids.uniq.each do |dispatch_plan_id|

    dispatch_plan = DispatchPlan.find(dispatch_plan_id)

    next unless dispatch_plan.present?

    begin
      add_name_to_address(dispatch_plan)
      p "Address updated for DP: #{dispatch_plan_id}"
      dp_data[dispatch_plan_id] = "Successfully Changed"
    rescue => e
      p "ERROR: Something went wrong when trying to change the company name: #{e}"
      dp_data[dispatch_plan_id] = "Failed to change"
    end

  end
  dp_data
end

def add_name_to_address(dispatch_plan)
  destination_address = dispatch_plan.destination_address
  if destination_address.company_name == "Urban Company"
    full_name = destination_address.full_name
    company_name = destination_address.company_name

    new_name = company_name + ": " + full_name #Preview- <Urban Company: Rajesh Motwani>

    destination_address.company_name = new_name
    destination_address.save(validate: false)
  else
    "Company name is already changed for address #{destination_address.company_name}"
  end
end