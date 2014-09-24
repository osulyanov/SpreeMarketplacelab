# Spree::Api::ProductsController.class_eval do
#   after_filter :notify_product_created, only: :create
#   after_filter :notify_product_updated, only: :update
#
#   def notify_product_created
#     # @product
#     marketplace_api = Marketplace::Api.instance
#     marketplace_api.create_product(@product)
#   end
#
#   def notify_product_updated
#     # @product
#     marketplace_api = Marketplace::Api.instance
#     marketplace_api.update_product(@product)
#   end
#
# end