# frozen_string_literal: true

def rerun_clickpost(dispatch_plans)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  counter = 0
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    shipment = dispatch_plan.shipment
    next unless shipment.present?

    counter += 1
    begin
      case shipment.status
      when 'ready_to_ship'
        shipment.update(transporter_id: dispatch_plan.suggested_transporter_id) if shipment.transporter_id.nil?
        if shipment.clickpost_tracking_id.nil? && shipment.tracking_id.present?
          RegisterAwbNumberToClickpostJob.perform_now(shipment.id)
          shipment.reload
          p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: TRUE, tracking manually updated [AWB registered]"
        elsif !shipment.packaging_labels.present?
          if shipment.no_of_packages != 1 && if_dpirs_belong_to_ppe_category(dispatch_plan)
            shipment.update(no_of_packages: 1)
          end
          result = Logistics::Clickpost::CreateOrder.new({ shipment_id: shipment.id })
          response = result.create_order
          if response.meta.status == 200 || response.meta.status == 323
            update_shipment(response, shipment.id)
            shipment.reload
            p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: TRUE, Labels Generated- #{shipment.packaging_labels.present?}"
          elsif response.meta.present? && response.meta.success == false && (response.meta.status == 319 || response.meta.status == 400)
            update_shipment_for_error(shipment.id, response.meta.message)
            p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: TRUE, Labels Generated- #{shipment.packaging_labels.present?}, ERROR: #{response.meta.message}"
          elsif response.meta.present? && response.meta.success == false && (response.meta.status != 323 && response.meta.status != 202 && response.meta.status != 102)
            p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: TRUE, Labels Generated- #{shipment.packaging_labels.present?}, ERROR: #{response.meta.message}"
          else
            p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: TRUE, Labels Generated- #{shipment.packaging_labels.present?}"
          end
        else
          p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: FALSE, Labels Generated- #{shipment.packaging_labels.present?}"
        end
      when 'dispatched'
        p "#{counter}. ALREADY DISPATCHED: DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Rerun: FALSE, Labels Generated- #{shipment.packaging_labels.present?}"
      end
    rescue StandardError => e
      p "#{counter}. ERROR[#{e}], Shipment ID- #{shipment.id}: Rerun: FALSE, Labels Generated- #{shipment.packaging_labels.present?}"
    end
  end
end

def if_dpirs_belong_to_ppe_category(dispatch_plan)
  dpirs = dispatch_plan.dispatch_plan_item_relations

  dpirs.each do |dpir|
    if dpir.product_details['category_hierarchy'].present? && dpir.product_details['sub_sub_category_id'].present?
      category_name = dpir.product_details['category_hierarchy'].first
      sub_sub_category_id = dpir.product_details['sub_sub_category_id']
    else
      product = Hashie::Mash.new(CataloguingService::Communicator.fetch_product(dpir.master_sku_id))
      sub_sub_category_id = product.category_id
      category = Hashie::Mash.new(CataloguingService::Communicator.fetch_category(sub_sub_category_id))
      category_name = category.category.hierarchy.first if category.category.present?
    end
    if category_name.present? && sub_sub_category_id.present? &&
       (APP_CONFIG['ppe_categories'].include?(category_name) || APP_CONFIG['ppe_ssc_ids'].include?(sub_sub_category_id) || APP_CONFIG['ppe_master_sku_ids'].include?(dpir.master_sku_id))
      return true
    end
  end

  false
end

def just_check_labels(dispatch_plans)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  counter = 0
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    shipment = dispatch_plan.shipment
    counter += 1
    if shipment.present?
      unless shipment.packaging_labels.present?
        p "#{counter}. DP- #{dispatch_plan_id}, Shipment ID- #{shipment.id}: Labels Generated- #{shipment.packaging_labels.present?}"
      end
      RegisterAwbNumberToClickpostJob.perform_now(shipment.id)
    else
      p "#{counter}. Shipment not found for DP ID: #{dispatch_plan_id}"
    end
  end
end

def update_shipment_for_error(shipment_id, error_message)
  shipment = Shipment.find_by_id(shipment_id)

  if shipment.present?
    shipment.clickpost_order_creation_errors = error_message
    unless shipment.save
      Rails.logger.error "Shipment clickpost order creation errors not updated because of #{shipment.errors.full_messages.join(', ')}"
    end
  end
end

def update_shipment(response, shipment_id)
  errors = []
  shipment = Shipment.find_by_id(shipment_id)

  ActiveRecord::Base.transaction do
    if shipment.present?
      shipment.tracking_id = response.result.waybill
      shipment.clickpost_tracking_id = response.result.waybill
      shipment.clickpost_order_creation_errors = ''

      unless shipment.save
        Rails.logger.error "Shipment tracking number and packaging label not updated because of #{shipment.errors.full_messages.join(', ')}"

        errors << shipment.errors.full_messages
      end

      packaging_label = PackagingLabel.new
      packaging_label.file = URI.open(response.result.label)
      packaging_label.shipment_id = shipment_id

      unless packaging_label.save
        Rails.logger.error "Packaging label not created for shipment id #{shipment_id} because #{packaging_label.errors.full_messages.join(', ')}"

        errors << packaging_label.errors.full_messages
      end
    end

    raise ActiveRecord::Rollback if errors.present?
  end

  shipment.generate_combined_invoice_label_file
end

def rerun_recommendation(dispatch_plans)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  counter = 0
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    # next if dispatch_plan.shipment.present?
    next if dispatch_plan.transporter_type == 'seller'

    counter += 1
    if !dispatch_plan.suggested_transporter_id.present?
      begin
        start_time = Time.now
        result = Logistics::Clickpost::TransporterRecommendation.new({ dispatch_plan_ids: [dispatch_plan_id] })
        response = result.recommended_transporter
        rec_end_time = Time.now
        if response.errors.present?
          p "#{counter}. DP- #{dispatch_plan_id}, Rerun: TRUE, Suggested transporter not added to DP(#{dispatch_plan_id}) because of #{response.errors.join(', ')} Execution Time: #{(rec_end_time - start_time) * 1000} ms"
        else
          update_dispatch_plan(dispatch_plan_id, response)
          end_time = Time.now
          dp = DispatchPlan.find(dispatch_plan_id)
          p "#{counter}. DP- #{dispatch_plan_id}, Rerun: TRUE, Recommended Transporter- #{Transporter.find(dp.suggested_transporter_id).name}, Recommendation Time: #{(rec_end_time - start_time) * 1000} ms, Total Execution Time: #{(end_time - start_time) * 1000} ms"
        end
      rescue StandardError => e
        p "#{counter}. DP- #{dispatch_plan_id}, Rerun: TRUE, Suggested transporter not added to DP(#{dispatch_plan_id}) because of #{e}"
      end
    else
      if dispatch_plan.shipment.present?
        shipment = dispatch_plan.shipment
        if shipment.suggested_transporter_id != dispatch_plan.suggested_transporter_id || shipment.suggested_transporter_name != dispatch_plan.suggested_transporter_name
          shipment.suggested_transporter_id = dispatch_plan.suggested_transporter_id
          shipment.suggested_transporter_name = dispatch_plan.suggested_transporter_name
          shipment.save!
        end
      end
      p "#{counter}. DP- #{dispatch_plan_id}, Rerun: FALSE, Recommended Transporter- #{dispatch_plan.suggested_transporter_name}"
    end
  end
end

def update_dispatch_plan(dispatch_plan_id, response)
  dispatch_plan = DispatchPlan.find_by_id(dispatch_plan_id)

  if dispatch_plan.present?
    transporter_name_hash = response[:result].first

    if transporter_name_hash.courier_partner_id.present?
      transporter = Transporter.by_click_post_id_accound_code(transporter_name_hash.courier_partner_account_code,
                                                              transporter_name_hash.courier_partner_id).first

      if transporter.present?
        dispatch_plan.suggested_transporter_id = transporter.id

        courier_partner_name = transporter_name_hash.courier_partner_name
        dispatch_plan.suggested_transporter_name = if !courier_partner_name.present?
                                                     transporter.name
                                                   else
                                                     courier_partner_name
                                                   end
      end

      unless dispatch_plan.save
        p "Suggested transporter not added to DP - #{dispatch_plan_id} because #{dispatch_plan.errors.full_messages.join(', ')}"
      end
    end
  end
end

def just_check_recommendation(dispatch_plans)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  counter = 0
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    counter += 1
    if dispatch_plan.suggested_transporter_name.present?
      p "#{counter}. DP- #{dispatch_plan_id}: Recommended Transporter- #{dispatch_plan.suggested_transporter_name}"
    else
      p "#{counter}. DP- #{dispatch_plan_id}: Recommended Transporter- NA"
    end
  end
end

#rerun_shipment_creation(dp_ids, "auto")
def rerun_shipment_creation(dispatch_plans, method)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  rerun_dps = []
  counter = 1
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    next if dispatch_plan.shipment.present?

    if dispatch_plan.origin_address.warehouse && dispatch_plan.ftl_flag != true # && APP_CONFIG["warehouse"]["automatic_shipments"].include?(dispatch_plan.origin_address.warehouse.id)
      begin
        p "#{counter}. Starting with Dispatch Plan: #{dispatch_plan_id}"
        create_invoice_data(dispatch_plan)

        case method
        when 'auto'
          AutoShipmentCreationForWToBDispatches.perform_later({ dispatch_plan_id: dispatch_plan_id })
        when 'manual'
          service = ShipmentServices::AutoShipmentCreationForWToBDispatches.new({ dispatch_plan_id: dispatch_plan_id })
          service.execute!
        else
          p "#{counter}. Invalid method(Choose auto/manual). No shipment created for DP #{dispatch_plan_id}"
        end

        shipment = dispatch_plan.shipment
        p "|->Shipment (#{shipment.id}) has been created successfully" unless shipment.nil?
      rescue StandardError => e
        p "||ERROR|| Shipment could not be created because of #{e}"
        rerun_dps.push(dispatch_plan_id)
      end
    else
      p "#{counter}. No shipment created for DP #{dispatch_plan_id} (Suggestion: #{dispatch_plan.suggested_transporter_name})"
      rerun_dps.push(dispatch_plan_id)
    end
    counter += 1
  end
  rerun_dps
end

def create_invoice_data(dispatch_plan)
  item_details = dispatch_plan.dispatch_plan_item_details
  dispatch_plan.update_dpir_product_details(item_details)
  dispatch_plan.update_company_snapshot(item_details)
end

def just_check_shipments(dispatch_plans)
  # dispatch_plans = [dispatch_plan_id1, dispatch_plan_id2, ....]
  dispatch_plans.each do |dispatch_plan_id|
    dispatch_plan = DispatchPlan.find(dispatch_plan_id)
    if dispatch_plan.shipment.present?
      p "Shipment created for #{dispatch_plan_id}: #{dispatch_plan.shipment.id}"
      p "Invoice created: #{dispatch_plan.shipment.buyer_invoice_no.present?}"
    else
      p "NOT CREATED for #{dispatch_plan.id}"
    end
  end
end
