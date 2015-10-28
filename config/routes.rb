Spree::Core::Engine.routes.draw do
  namespace :admin do
    get "listings", to: "listings#index"
    get "marketplace_configuration", to: "marketplace_configuration#edit"
    put "marketplace_configuration", to: "marketplace_configuration#update"
    resource :marketplace_configuration, only: [:edit, :update]
  end

  namespace :marketplace, defaults: { format: 'json' } do
    post "/listener/listing" => "listener#listing"
    post "/listener/order" => "listener#order"
    post "/listener/order_dispatched" => "listener#order_dispatched"
    post "/listener/order_unable_to_dispatch" => "listener#order_unable_to_dispatch"
    post "/listener/order_awaiting_dispatch" => "listener#order_awaiting_dispatch"
    post "/listener/product" => "listener#product"
  end
end
