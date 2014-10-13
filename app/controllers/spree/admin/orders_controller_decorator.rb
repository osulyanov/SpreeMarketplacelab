Spree::Admin::OrdersController.class_eval do
  after_filter :notify_order_cancelled, only: :cancel

  def notify_order_cancelled
    # @order
    api = Marketplace::Api.instance
    api.cancel_order(@order)
  end

end