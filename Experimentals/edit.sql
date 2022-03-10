select distinct dpir.dispatch_plan_id, dpir.master_sku_id,
dpir.quantity total_quantity, dp.created_at,

    case
       when dp.status = 1 then (select
                                case
                                    when t.completion_date is not null then t.completion_date
                                    else t.deadline
                                end as c_date
                                from timelines t where t.dispatch_plan_id = dp.id and timeline_type = 5)
       else (select original_deadline from timelines t where t.dispatch_plan_id = dp.id and timeline_type = 5)
    end as delivery_timeline_date,

    case
        when dp.dispatch_mode = 4 then 'Warehouse to Warehouse'
        when dp.dispatch_mode = 1 then 'Seller to Warehouse'
        when dp.dispatch_mode = 2 then 'Warehouse to Buyer'
        else 'Buyer to Warehouse return'
    end as dispatch_mode,
    case
        when (select id from shipments s where s.dispatch_plan_id = dp.id) is null then 0
        else (select id from shipments s where s.dispatch_plan_id = dp.id)
    end as shipment_id,
    case
        when (select s.id from shipments s where s.dispatch_plan_id = dp.id) is null then 'No Shipment'
        when (select s.status from shipments s where s.dispatch_plan_id = dp.id) = 0 then 'Ready to Ship'
        when (select s.status from shipments s where s.dispatch_plan_id = dp.id) = 1 then 'Dispatched'
        when (select s.status from shipments s where s.dispatch_plan_id = dp.id) = 2 then 'Delivered'
        when (select s.status from shipments s where s.dispatch_plan_id = dp.id) = 3 then 'Cancelled'
        when (select s.status from shipments s where s.dispatch_plan_id = dp.id) = 5 then 'Lost'
        else 'Returned'
    end as shipment_status,
    case
        when dp.dispatch_mode in (2, 4) then (select warehouse_name from warehouses where to_json(id)::text = cast(dp.origin_address_snapshot::json->>'addressable_id' as text))
        else cast(dp.origin_address_snapshot::json->>'company_name' as text)
    end as outward_from,
    case
        when dp.dispatch_mode in (1, 3, 4) then (select warehouse_name from warehouses where to_json(id)::text = cast(dp.destination_address_snapshot::json->>'addressable_id' as text))
        else cast(dp.destination_address_snapshot::json->>'company_name' as text)
    end as inward_in,

    case
        when dp.status = 0 then 'Open'
        when dp.status = 1 then 'Done'
        else 'Cancelled'
    end as dp_status

from dispatch_plan_item_relations dpir, dispatch_plans dp, warehouses w
where dpir.dispatch_plan_id = dp.id
[[and dpir.master_sku_id = {{master_sku}}]]
and w.id in (select id from warehouses [[where {{warehouse_name}}]])
and dp.id in
    (select id from dispatch_plans
        [[where {{updated_at}}]]
        [[and {{dispatch_mode}}]]
        [[and {{DP_Status}}]])
and (cast(dp.destination_address_snapshot::json->>'addressable_id' as text) = to_json(w.id)::text)
    or
    (cast(dp.origin_address_snapshot::json->>'addressable_id' as text) = to_json(w.id)::text)
and dp.dispatch_mode in (1, 2, 3, 4)