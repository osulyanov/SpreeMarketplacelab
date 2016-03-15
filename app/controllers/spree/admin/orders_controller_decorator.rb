Spree::Admin::OrdersController.class_eval do
  after_filter :notify_order_cancelled, only: :cancel

  def notify_order_cancelled
    # @order
    api = Marketplace::Api.instance
    success, response = api.cancel_ml_order_v2(order, "Cancelled within Spree Admin")
    if success 
      Spree::OrderMailer.canceled(order, @seller, "Cancelled within Spree Admin").deliver!
      flash[:error] = "<strong>Order cancelled!</strong>"
    else
      Rails.logger.warn "Order Cancellation Failed - Marketplace error; response: #{response.inspect}"
      flash[:success] = nil
      flash[:error] = "Sorry the Order could not be Cancelled at this time. If necessary please speak to the Marketplace Technical Support team to investigate the reason why."
    end
  end
end
