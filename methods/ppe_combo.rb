# input = "<group_name>"
def create_group(names)
  names.each do |name|
    if !Group.where(name: name).present?
      Group.create(name: name)
      p "SUCCESS: A group with name: #{name} created successfully.."
    else
      p "ERROR: A group with name '#{name}' already exist.."
    end
  end
end


# input = [[master_sku_id, priority, group], [master_sku_id_1, priority_1, group_1], ...]
def assign_group(sku_priority_data)
  sku_priority_data.each do |sku_priority|
    master_sku_id = sku_priority[0]
    group_id = sku_priority[2]
    priority = sku_priority[1]
    counter = 0
    if Group.find(group_id).present?
      counter += 1
      if MasterSku.find(master_sku_id).present? && !GroupMasterSkuPriority.where(master_sku_id: master_sku_id, group_id: group_id).present?
        begin
        GroupMasterSkuPriority.create(master_sku_id: master_sku_id, group_id: group_id, priority: priority)
        p "#{counter}. SUCCESS: Group (#{group_id}) and SKU (#{master_sku_id}) mapped with priority #{priority}"
        rescue => e
          p "#{counter}. ERROR: Group ID could not be assigned to SKU: #{master_sku_id} (#{e})"
        end
      elsif MasterSku.find(master_sku_id).present?
        p "#{counter}. ERROR: Master SKU #{master_sku_id} already belongs to Group ID: #{group_id}"
      else
        p "#{counter}. ERROR: Master SKU ID #{master_sku_id} couldn't be found..."
      end
    else
      p "ERROR: Group ID (#{group_id}) does not exist"
    end
  end
end


# mapping_data = [[group_id_1, multiplier], [group_id_2, multiplier], ...]
# input = (master_sku_id, mapping_data)
def create_group_mapping(master_sku_id, mapping_data)
  parent_sku = MasterSku.find(master_sku_id)
  counter = 0
  if parent_sku.present?
    p "-------------- Starting group mapping for Parent SKU: #{parent_sku.id} --------------"
    counter += 1
    mapping_data.each do |ref|
      group_id = ref[0]
      multiplier = ref[1]
      next if GroupMapping.where(master_sku_id: master_sku_id, group_id: group_id).present?
      if Group.find(group_id).present? && GroupMasterSkuPriority.where(group_id: group_id).present?
        GroupMapping.create(master_sku_id: parent_sku.id, group_id: group_id, multiplier: multiplier)
        p "#{counter}. SUCCESS: A group mapping has been created with group ID (#{group_id}), Multiplier (#{multiplier})"
        parent_sku.update(is_ppe: true) unless parent_sku.is_ppe == true
      elsif Group.find(group_id).present? && GroupMasterSkuPriority.where(group_id: group_id).nil?
        p "#{counter}. ERROR: Group ID #{group_id} does not have any SKU mapped to it"
      else
        p "#{counter}. ERROR: Group ID (#{group_id}) does not exist"
      end
    end
  else
    p "ERROR: Master SKU ID #{master_sku_id} couldn't be found..."
  end
end