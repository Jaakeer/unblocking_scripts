def advance_adjustment
  output = "Initialized"
  invalid_input = "That's not a valid input please try again"
  loop do
    p "Main Menu"
    p "1. Advance Movement"
    p "clickpost_sample.json. Advance Merging"
    p "3. Create Settlement"
    p "4. Remove Settlement"
    p "5. Exit"
    first_input = gets.strip
    case(first_input.to_i)
    when 1
      loop do
        p "::::::::::: Advance Movement :::::::::::"
        p "1. 100% movement of advance"
        p "clickpost_sample.json. Partial movement of advance"
        p "3. Exit"
        second_input = gets.strip
        case(second_input.to_i)
        when 1
          p "Move total advance from one PO to another"
          p "Provide the paid Bizongo Purchase Order.."
          po = get.strip
          po_id = check_po(po)
          if po_id.present?
            p "Provide the Bizongo Purchase Order you want to move the advance to.."
            final_po = get.strip
            final_po_id = check_po(final_po)
            move_advance(po_id, final_po_id)
          end
        when 2
          p "#{second_input}"
        when 3
          break
        else
          p "#{invalid_input}"
        end
      end
    when 2
    when 5
      p "------------------- Thank You -------------------"
      output = "Connection Closed"
      break
    else
      p "#{invalid_input}"
    end
  end

  return output
end

def check_po(po)

end

def find_advance(po_id)
  advance_settlement = AdvanceAdjustment.where(bizongo_purchase_order_id: po_id)
end

def move_advance(po_id, final_po_id)