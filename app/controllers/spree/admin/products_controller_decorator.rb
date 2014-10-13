Spree::Admin::ProductsController.class_eval do
  after_filter :notify_product_created, only: :create
  after_filter :notify_product_updated, only: :update

  def notify_product_created
    # @product
    api = Marketplace::Api.instance
    api.create_product(@product)
  end

  def notify_product_updated
    # @product
    api = Marketplace::Api.instance
    api.update_product(@product)
  end

end