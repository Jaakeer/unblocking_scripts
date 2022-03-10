def update_dispatch_plan_on_scheduling_service(dispatch_plan_id, address_id)
  dispatch_plan = DispatchPlan.find(dispatch_plan_id)
  segment_update_params = { id: dispatch_plan.segment_id, type: 'segment_type_change' }.merge({ segment_update_params: @dispatch_plan_params.merge({ origin_address_snapshot: Address.find(@dispatch_plan_params[:origin_address_id]) }) })
  segment_updated = SchedulingService::Communicator.update_segment(segment_update_params)
end
