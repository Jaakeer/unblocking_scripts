def create_bulk_products(product_data_set)
  product_data_set.each do |product_data|
    product_name = product_data[0]
      ...

  end
end


def create_product_params(product_creation_params)
  product_params = {}
  product_params <<
    {product_name: product_creation_params[:product_name],
    alias_product_name: product_creation_params[:alias_product_name],
    item_code: product_creation_params[:item_code],
    category_reference_id: product_creation_params[:category_reference_id],
    new_product_id: product_creation_params[:new_product_id],
    hsn_id: product_creation_params[:hsn_id],
    company_reference_id: product_creation_params[:category_reference_id]
    }
  product_params
end

def create_product(product_params)
  add_to_catalogue_response = Hashie::Mash.new(CataloguingService::Communicator.add_to_catalogue(
    centre_product_hash(product_params)
  ))
  add_to_catalogue_response
end

def centre_product_hash(product_params)
  if product_params.hsn_id.present?
    hsn = Hashie::Mash.new(TaxationService::Communicator.fetch_gst_hsn_details(product_params.hsn_id))
  else
    hsn = Hashie::Mash.new(TaxationService::Communicator.fetch_category_gst_hsn( product_params.category_reference_id,1))
  end
  centres = Hashie::Mash.new(Bizongo::Communicator.fetch_centres(product_params.company_reference_id)).try(:centres)
  centre_ids = centres.map {|element| element.id if element.is_hq == true}.compact
  {
    product_id: product_params.new_product_id,
    master_hsn_id: hsn.hsnGstDetails.id,
    client_id: product_params.company_reference_id,
    active: true,
    centres: centre_ids
  }
end
