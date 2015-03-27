Spree::Admin::OrdersController.class_eval do
  after_filter :notify_order_cancelled, only: :cancel

  def notify_order_cancelled
    # @order
    api = Marketplace::Api.instance
    if !api.cancel_order(@order)
      flash[:success] = nil
      flash[:error] = "Sorry the Order could not be Cancelled at this time. If necessary please speak to the Marketplace Technical Support team to investigate the reason why."
    end
  end

end