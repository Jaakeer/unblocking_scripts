select s.id reference_number,
       case
           when dp.dispatch_mode = 0 then 'Seller to Buyer'
           when dp.dispatch_mode = 1 then 'Seller to Warehouse'
           when dp.dispatch_mode = 2 then 'Warehouse to Buyer'
           when dp.dispatch_mode = 3 then 'Buyer to Warehouse'
           when dp.dispatch_mode = 4 then 'Warehouse to Warehouse'
           else 'Buyer to Seller'
        end as dispatch_mode,
        case
            when s.buyer_invoice_no is not null then 'Present'
            when s.buyer_delivery_challan_no is not null then 'Present'
            else 'Not Present'
        end as invoice_number,
        case
            when s.total_buyer_invoice_amount is not null then 'Present'
            else 'Not Present'
        end as invoice_value,
        case
            when t.clickpost_cp_id is not null then 'Present'
            else 'Not Present'
        end as courier_partner,
        case
            when s.weight is not null then 'Present'
            else 'Not Present'
        end as weight,
        case
            when t.clickpost_account_code is not null then 'Present'
            else 'Not Present'
        end as clickpost_account_code,
        case
           when s.no_of_packages > 1 then 'Correct'
           when dpir.pack_size > 1 then 'Correct'
           else 'Pack Size Incorrect'
        end as quantity,
        case
            when cast(dp.origin_address_snapshot::json->>'company_name'::text) is not null then 'Present'
            else 'Not Present'
        end as supplier_name,
        case
            when cast(dp.origin_address_snapshot::json->>'mobile_number'::text) is not null then 'Present'
            else 'Not Present'
        end as phone,
        case
            when cast(dp.origin_address_snapshot::json->>'street_address'::text) is not null then 'Present'
            else 'Not Present'
        end as address
from shipments s, transporter t, dispatch_plans dp, dispatch_plan_item_relations dpir
where s.transporter_id = t.id
  and s.dispatch_plan_id = dp.id
  and dpir.dispatch_plan_id = dp.id
  and s.transporter_type = 'bizongo'