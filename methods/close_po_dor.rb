class DirectOrderServices::CancelDirectOrder < BaseService
    include ConfigUtil
    attr_reader :result
    attr_reader :status

    def initialize(direct_order_id)
        super()
        @direct_order = DirectOrder.find(direct_order_id)
        @rollback_failed_orders = []
        @order_item_dps_production = {}
        @order_item_dps_planning = {}
        @result = {}
        @status = @direct_order.status
        @dps_to_be_cancelled = []
    end

    def execute
        ActiveRecord::Base.transaction do
            return false unless super
            check_open_pos
            get_all_planned_dispatches
            populate_variables
            rollback_orders if @order_item_dps_planning.size >= 0 && @order_item_dps_production.size > 0
            close_dor
            @dps_to_be_cancelled.reject! {|x| x == 0}
            mark_dp_cancelled unless @dps_to_be_cancelled.blank?
            raise BizongoValidationError, errors.join(",") unless errors.blank?
            prepare_result
        end
    end

    private

    def validate
        super
        error "Direct Order is already cancelled" if @direct_order.cancelled?
        error "Direct Order is already completed" if @direct_order.completed?
        error "Direct Order is already returned" if @direct_order.returned?
        error "Direct Order is already short closed" if @direct_order.short_closed?
    end

    def prepare_result
        @order_item_dps_planning.each do |order_item_id, value|
            dispatch_plans = value[:dispatch_plans]
            entries = []
            dispatch_plans.each do |dispatch_plan|
                entries << result_entry(dispatch_plan, "Planning")
            end
            @result.key?(order_item_id) ? @result[order_item_id] += entries : @result[order_item_id] = entries
        end
        @order_item_dps_production.each do |order_item_id, value|
            dispatch_plans = value[:dispatch_plans]
            entries = []
            dispatch_plans.each do |dispatch_plan|
                entries << result_entry(dispatch_plan, "Production")
            end
            @result.key?(order_item_id) ? @result[order_item_id] += entries : @result[order_item_id] = entries
        end
        @status = @direct_order.reload.status
        @result.each do |order_item, dps|
            total_rollback = 0
            total = 0
            dps.each do |dp|
                if dp[:status] == "Planning"
                    total_rollback += dp[:quantity]
                end
                total += dp[:quantity]
            end
            dps.first[:total_rollback] = total_rollback
            dps.first[:total] = total
        end
    end

    def result_entry(dispatch_plan, status)
        {
            id: dispatch_plan[:id],
            quantity: dispatch_plan[:quantity],
            status: status,
            action: dispatch_plan[:reason]
        }
    end

    def populate_variables
        return unless valid?
        @dpirs.each do |dpir|
            if dpir.dispatch_plan_status == "open"
                case dpir.dispatch_mode
                when "warehouse_to_buyer"
                    dpir.pick_generated ? update_order_item_dp_prodution(dpir.order_item_id, dpir.quantity, dpir.dispatch_plan_id, "Cannot be rolled back as pick is created") : update_order_item_dp_planning(dpir.order_item_id, dpir.quantity, dpir.dispatch_plan_id)
                when "seller_to_buyer"
                    update_order_item_dp_prodution(dpir.order_item_id, dpir.shipped_quantity, dpir.dispatch_plan_id, "Cannot be rolled back as seller started processing")
                when "seller_to_warehouse"
                    update_order_item_dp_prodution(dpir.order_item_id, dpir.shipped_quantity, dpir.dispatch_plan_id, "Cannot be rolled back as seller started processing")
                when "buyer_to_warehouse"
                    update_order_item_dp_prodution(dpir.order_item_id, dpir.shipped_quantity, dpir.dispatch_plan_id, "Cannot be rolled back as currently do not support return")
                when "buyer_to_seller"
                    update_order_item_dp_prodution(dpir.order_item_id, dpir.shipped_quantity, dpir.dispatch_plan_id, "Cannot be rolled back as currently do not support return")
                end
            elsif dpir.dispatch_plan_status != "cancelled"
                update_order_item_dp_prodution(dpir.order_item_id, dpir.shipped_quantity, dpir.dispatch_plan_id, "Cannot be rolled back as dispatch plan is #{dpir.dispatch_plan_status}")
            end
        end
    end

    def get_all_planned_dispatches
        response = SupplyDispatcher::Communicator.dispatch_plan_relation_index!(order_item_ids: @direct_order.order_items.pluck(:id), no_pagination: true)
        @dpirs = Hashie::Mash.new(response).dispatch_plans
    end

    def update_order_item_dp_planning(order_item_id, quantity, dispatch_plan_id)
        if @order_item_dps_planning.key?(order_item_id)
            @order_item_dps_planning[order_item_id][:rollback_quantity] += quantity
            @order_item_dps_planning[order_item_id][:dispatch_plans] << {id: dispatch_plan_id, quantity: quantity, reason: "Cancelled"}
        else
            @order_item_dps_planning[order_item_id] = {rollback_quantity: quantity, dispatch_plans: [{id: dispatch_plan_id, quantity: quantity, reason: "Cancelled"}]}
        end
    end

    def update_order_item_dp_prodution(order_item_id, quantity, dispatch_plan_id, reason)
        if @order_item_dps_production.key?(order_item_id)
            @order_item_dps_production[order_item_id][:cant_rollback_quantity] += quantity
            @order_item_dps_production[order_item_id][:dispatch_plans] << {id: dispatch_plan_id, quantity: quantity, reason: reason}
        else
            @order_item_dps_production[order_item_id] = {cant_rollback_quantity: quantity, dispatch_plans: [{id: dispatch_plan_id, quantity: quantity, reason: reason}]}
        end
    end

    def close_dor
        if @order_item_dps_production.size == 0 && @order_item_dps_planning.size >= 0
            @direct_order.cancelled!
            response = SupplyDispatcher::Communicator.dispatch_plan_status_change({status: "cancelled", order_item_ids: @direct_order.order_items.pluck(:id)})
            error response["error"] if response["error"].present?
        elsif @order_item_dps_planning.size > 0 && @order_item_dps_production.size > 0
            @direct_order.completed!
        end
    end

    def rollback_orders
        update_no_dp_quantity
        @order_item_dps_planning.each do |order_item_id, hash|
            @order_item = OrderItem.find(order_item_id)
            @order_item_cancelled = false
            @rollback_quantity = hash[:rollback_quantity].to_i
            update_order_item
            update_delivery_request unless @order_item_cancelled
            update_po_items
            @dps_to_be_cancelled += hash[:dispatch_plans].map {|h| h[:id]}
        end
    end

    def update_no_dp_quantity
        @direct_order.order_items.each do |order_item|
            @order_item = order_item
            @order_item_cancelled = false
            no_dp_quantity = find_non_prod_plan_quantity(order_item, order_item.product_quantity * @order_item.sku_value.to_i)
            update_order_item_dp_planning(order_item.id, no_dp_quantity, 0) if no_dp_quantity > 0
        end
    end

    def find_non_prod_plan_quantity(order_item, total_quantity)
        planned_quantity = 0
        production_quantity = 0
        @order_item_dps_planning.each do |order_item_id, hash|
            planned_quantity += hash[:rollback_quantity] if order_item_id == order_item.id
        end
        @order_item_dps_production.each do |order_item_id, hash|
            production_quantity += hash[:cant_rollback_quantity] if order_item_id == order_item.id
        end
        total_quantity - planned_quantity - production_quantity
    end

    def return_case
        "cannot be handled currently because we do not have short close on dor which will impact gmv
      also if we reduce the quantity then the problem will be , how did we create a dp of quantity>order_item_quantity"
    end

    def update_order_item
        if @order_item.product_quantity - @rollback_quantity / @order_item.sku_value.to_i != 0
            @order_item.product_quantity = @order_item.product_quantity - @rollback_quantity / @order_item.sku_value.to_i
            @order_item.placed_quantity = @order_item.placed_quantity - @rollback_quantity / @order_item.sku_value.to_i
            @order_item.save!
        else
            cancel_order_item
        end
    end

    def cancel_order_item
        @order_item_cancelled = true
        @order_item.delivery_status = "cancelled"
        @order_item.save!
    end

    def update_po_items
        po_item = get_po_item
        error "Purchase order item not found for order_item_id #{@order_item.id}" if po_item.nil?
        return if po_item.nil?
        po_item.open_quantity = po_item.calculate_open_quantity
        po_item.save!
    end

    def get_po_item
        po_items = @order_item.direct_order.try(:delivery_group).try(:purchase_order).try(:purchase_order_items)
        return if po_items.nil?
        po_items.where(child_product_id: @order_item.child_product_id).first
    end

    def update_delivery_request
        delivery_request_item = get_delivery_request_item
        error "Delivery request item not found for order_item_id #{@order_item.id}" if delivery_request_item.nil?
        return if delivery_request_item.nil?
        delivery_request_item.quantity -= @rollback_quantity
        delivery_request_item.quantity.zero? ? delivery_request_item.destroy : delivery_request_item.save!
    end

    def get_delivery_request_item
        delivery_request_item = nil
        @order_item.direct_order.delivery_group.delivery_requests.each do |dr|
            if dr.actual_shipping_address_id == @order_item.direct_order.shipping_address.id
                dr.delivery_request_items.each do |dri|
                    if dri.child_product_id == @order_item.child_product_id
                        delivery_request_item = dri
                        break
                    end
                end
            end
        end
        delivery_request_item
    end

    def mark_dp_cancelled
        response = SupplyDispatcher::Communicator.dispatch_plan_status_change({status: "cancelled", dispatch_plan_ids: @dps_to_be_cancelled})
        error response["error"] if response["error"].present?
    end

    def check_open_pos
        @direct_order.order_items.each do |order_item|
            bizongo_po_items = BizongoPoItem.where(order_item_id: order_item.id)
            bizongo_po_items.each do |bizongo_po_item|
                hanging = 0
                if bizongo_po_item.bizongo_purchase_order.status == "short_closed"
                    response = SupplyDispatcher::Communicator.dispatch_plan_relation_index!(bizongo_po_item_ids: [bizongo_po_item.id], dispatch_plan_status: ["open", "done"], no_pagination: true)
                    dpirs = Hashie::Mash.new(response).dispatch_plans
                    dpirs.each do |dpir|
                        hanging += dpir.hanging_quantity.to_i if dpir.order_item_id == bizongo_po_item.order_item_id
                    end
                    update_order_item_dp_planning(order_item.id, hanging, "NA") if hanging > 0
                elsif  !dp_exists?(bizongo_po_item) && bizongo_po_item.bizongo_purchase_order.status != "cancelled"
                    update_order_item_dp_prodution(order_item.id, bizongo_po_item.quantity, "NA", "Cannot be cancelled as Seller PO exist, Cancel the PPO first and proceed")

                #elsif bizongo_po_item.bizongo_purchase_order.status == "pending"
                #   po = bizongo_po_item.bizongo_purchase_order
                #   po.status = "cancelled"
                #   if po.save
                #      update_order_item_dp_planning(order_item.id, bizongo_po_item.quantity, "NA")
                #    end
                end
            end
        end
    end

    def dp_exists?(bizongo_po_item)
        response = SupplyDispatcher::Communicator.dispatch_plan_relation_index!(bizongo_po_item_ids: [bizongo_po_item.id], no_pagination: true)
        dpirs = Hashie::Mash.new(response).dispatch_plans
        return false unless dpirs.present?
        dpirs.each do |dpir|
            if dpir.order_item_id == bizongo_po_item.order_item_id
                return true
            end
        end
        false
    end
    # Keeping this code if needed in future to delete PRs
    # def delete_open_prs
    #   if delivery_group.seller_po_requests.present?
    #     delivery_group.seller_po_requests.each do |pr|
    #       child_product_relations = pr.seller_po_request_child_product_relations
    #       seller_po_versions = pr.seller_po_versions
    #       if child_product_relations.present? && seller_po_versions.present? && no_accepted_seller_po?(pr)
    #         child_product_relations.each do |child_product_relation|
    #           child_product_relation.delete
    #           seller_po_versions.each(&:delete)
    #         end
    #         pr.delete
    #       end
    #     end
    #   end
    # end
    #
    # def no_accepted_seller_po?(pr)
    #   flag = true
    #   pr.seller_po_request_bizongo_po_relations.each do |relation|
    #     seller_po = BizongoPurchaseOrder.find_by_id(relation.bizongo_purchase_order_id)
    #     if seller_po.present? && seller_po.status != "pending"
    #       flag = false
    #       break
    #     end
    #   end
    #   flag
    # end
end