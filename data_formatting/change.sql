SELECT "supply_chain"."dispatch_plans"."id" AS "DP ID",
       "Shipments"."id"               as "Shipment ID",
       case
           when "Shipments"."status" = '0' then ' Ready to Ship '
    when "Shipments"."status" = '1' then ' Dispatched '
    when "Shipments"."status" = '2' then ' Delivered '
    when "Shipments"."status" = '3' then ' Cancelled '
    when "Shipments"."status" = '4' then ' Could not deliver '
    when "Shipments"."status" = '5' then ' Shipment lost '
    when "Shipments"."status" = '6' then ' Returned '
end as "Shipment status",
case
when "supply_chain"."dispatch_plans"."dispatch_mode" = '0' then 'S2B'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '1' then 'S2W'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '2' then 'W2B'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '3' then 'B2W'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '4' then 'W2W'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '5' then 'W2S'
when "supply_chain"."dispatch_plans"."dispatch_mode" = '6' then 'B2S'
end as "Dispatch Mode",
case
when "supply_chain"."dispatch_plans"."status" = '0' then 'Open'
when "supply_chain"."dispatch_plans"."status" = '1' then 'Done'
when "supply_chain"."dispatch_plans"."status" = '2' then 'Cancelled'
end as "DP status",
"Dispatch Plan Item Relations"."master_sku_id" as "SKU Code",
"Dispatch Plan Item Relations"."product_details"::json->>'product_name' as "Product Name",
"supply_chain"."dispatch_plans"."created_at" as "DP Created",
"Shipments"."created_at" as "Shipment Created At",
"Shipments"."delivered_at" as "Shipment Delivered date",
"Shipments"."buyer_invoice_no" as "Invoice Number",
"Shipments"."total_buyer_invoice_amount" AS "total_buyer_invoice_amount",
"supply_chain"."dispatch_plans"."destination_address_snapshot"::json->>'id' as "Address ID",
"supply_chain"."dispatch_plans"."destination_address_snapshot"::json->>'alias' as "Address Alias",
"supply_chain"."dispatch_plans"."destination_address_snapshot"::json->>'company_name' as "Company Name",
"supply_chain"."dispatch_plans"."destination_address_snapshot"::json->>'pincode' as "Pincode",
"Shipments"."tracking_id" as "Tracking Id",
"supply_chain"."dispatch_plans"."pick_list_file" as "PickList File",
"supply_chain"."dispatch_plans"."region" as "DP Region",
"Shipments"."region" as "Shipment Region",
CONCAT('https://leadplus.bizongo.in/direct-order/',"Shipments"."direct_order_id") as "Direct Order"
FROM "supply_chain"."dispatch_plans"
LEFT JOIN "supply_chain"."dispatch_plan_item_relations" "Dispatch Plan Item Relations" ON "supply_chain"."dispatch_plans"."id" = "Dispatch Plan Item Relations"."dispatch_plan_id"
LEFT JOIN "supply_chain"."shipments" "Shipments" ON "supply_chain"."dispatch_plans"."id" = "Shipments"."dispatch_plan_id"
WHERE cast("supply_chain"."dispatch_plans"."destination_address_snapshot"::json->>'centre_id' as int) in ('19249') 
or cast("supply_chain"."dispatch_plans"."origin_address_snapshot"::json->>'centre_id' as int) in ('19249')
and {{shipment_status}}
and {{dp_created}}
and {{shipment_created}}
and {{shipment_delivered}}
and {{DPID}}
order by "supply_chain"."dispatch_plans"."id" desc