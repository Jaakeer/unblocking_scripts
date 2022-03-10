def create_location(warehouse_id)
  code_base = "BZ-GF-"
  (301..1000).each { |i|
    code = code_base + i.to_s
    Location.create(code: code, warehouse_id: warehouse_id)
    p "Location created #{code}"
  }
end
