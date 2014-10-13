Spree::CheckoutController.class_eval do
  after_filter :after_update, only: :update

  def after_update
    if @order.state == "complete"
      api = Marketplace::Api.instance
      api.create_order(@order)
    end
  end
end