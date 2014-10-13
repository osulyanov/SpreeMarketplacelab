require 'httparty'

module Marketplace
  class Api
    include Listenable

    def initialize(api_key, account_key, api_base_url)
      @api_key = api_key
      @account_key = account_key
      @api_base_url = api_base_url
    end

    def self.instance
      @instance ||= begin
        api_key = SpreeMarketplacelab::Config[:apiKey]
        account_key = SpreeMarketplacelab::Config[:accountKey]
        api_base_url = SpreeMarketplacelab::Config[:apiBaseUrl]

        self.new(api_key, account_key, api_base_url)
      end
    end

    def dispatch_order(store_order_id)
      dispatch_model = {
        StoreOrderId: store_order_id,
        DispatchDate: Time.now.strftime("%Y-%m-%d %H:%M")
      }.to_json

      post_api_response("/api/orders/#{store_order_id}/dispatch", "", dispatch_model)
    end

    def get_dispatch_status(store_product_id)
      get_api_response("/api/orders/dispatchstatus", "storeProductId=#{store_product_id}", true)
    end

    def create_listing(spree_product, spree_user, sub_condition)
      listing_model = {
        SKU: spree_product.sku,
        StoreProductId: spree_product.sku,
        Upc: spree_product.sku,
        Title: spree_product.name,
        ItemNote: spree_product.description,
        Condition: "Used",
        SubCondition: sub_condition,
        DispatchedFrom: "GB",
        DispatchedTo: "UK",
        QuantityAvailable: 1,
        ListingPrices: [
          {
            Amount: spree_product.price,
            CurrencyType: "GBP",
            ListingPriceId: 3 # AskingPrice
          },
          {
              Amount: spree_product.retail_price,
              CurrencyType: "GBP",
              ListingPriceId: 4 # RetailPrice
          },
          {
              Amount: spree_product.best_offer_price,
              CurrencyType: "GBP",
              ListingPriceId: 5 # BestOfferPrice
          }
        ],
        DeliveryPrices: nil,
        ProductIdType: "UPC",
        CustomAttributes: {
          Width: spree_product.width.to_s,
          Height: spree_product.height.to_s,
          Depth: spree_product.depth.to_s,
          Weight: spree_product.weight.to_s,
        },
        Category: spree_product.major_category,
        Images: [
          {
            ImageUrl: spree_product.images[0].attachment.url,
            ImageType: "Large"
          }
        ],
        StoreCustomerId: spree_user.email,
        Comment: "From Furniture"
      }.to_json

      post_api_response("/api/listings/selleremail", "sellerEmail=#{spree_user.email}", listing_model)
    end

    def create_product(spree_product)
      marketplace_product_json = {
          UPC: spree_product.sku,
          StoreProductId: spree_product.sku,
          Title: spree_product.name,
          Price: {
              Currency: "GBP",
              Amount: spree_product.price
          }
      }.to_json

      post_api_response('/api/products', '', marketplace_product_json)
    end

    def update_product(spree_product)

    end

    def get_best_prices(product_ids)
      get_api_response("/api/products/#{product_ids}/listings?condition=new&view=bestprices")
    end

    def create_order(spree_order)
      marketplace_order_json = convert_to_marketplace_order(spree_order)
      if (post_api_response('/api/orders/create', '', marketplace_order_json))
        marketplace_order_adjustment = convert_to_order_adjustment(spree_order, 'AwaitingDispatch')
        post_api_response('/api/orders/' + spree_order.number + '/adjustment', '', marketplace_order_adjustment)
      end
    end

    def cancel_order(spree_order)
      marketplace_order_adjustment = convert_to_order_adjustment(spree_order, 'Cancelled')
      post_api_response('/api/' + spree_order.number + '/adjustment', '', marketplace_order_adjustment)
    end

    def notify(event_name, data)
      notify_listeners(event_name, data)
    end

    # @listing_ids comma separated list of listings identifiers
    def get_deliveryoptions(listing_ids, country_code)
      get_api_response("/api/listings/#{listing_ids}/shippingmethods/#{country_code}")
    end

    # get listings for a product(s)
    # @product_ids comma separated list of product identifiers
    def get_listings(product_ids)
      get_api_response("/api/products/#{product_ids}/listings")
    end

    def get_listing(listing_id)
      listing = get_api_response("/api/listings/#{listing_id}")
      listing[0] if listing && listing.any?
    end

    def subscribe_to_webhooks
      subscribe_to :listing_created
    end

    private
      def convert_to_order_adjustment(spree_order, adjustment_type)
        adjustment_dto = {
            CustomerEmail: spree_order.email,
            StoreOrderId: spree_order.number,
        }

        adjustment_dto[:Adjustments] = []
        spree_order.line_items.each { |item|
          adjustment_dto[:Adjustments].push({
                                                StoreOrderItemId: spree_order.number + "-" + item.id.to_s,
                                                Quantity: item.quantity,
                                                Price: item.price,
                                                AdjustmentType: adjustment_type
                                            })
        }

        return adjustment_dto.to_json
      end

      def convert_to_marketplace_order(spree_order)
        order_dto = {
            StoreOrderId: spree_order.number,
            SellerOrderId: spree_order.number,
            CustomerEmail: spree_order.email,
            CustomerTitle: "",
            CustomerFirstName: "First",
            CustomerLastName: "Last",
            StoreOrderDate: spree_order.created_at,
        }

        order_dto[:OrderItems] = []

        spree_order.line_items.each { |item|
          listing = item.listing
          order_dto[:OrderItems].push({
                                          ListingId: listing[:id],
                                          PaymentStatus: 30, # Paid
                                          ShippingStatus: 10, # Pending
                                          Quantity: item.quantity,
                                          Price: item.price,
                                          StoreOrderItemId: spree_order.number + "-" + item.id.to_s,
                                          StoreProductId: item.variant.sku,
                                          SellerId: listing[:seller_id],
                                          ListingDispatchFromCountryId: 235,
                                          ListingConditionId: 1,
                                          ListingSubConditionId: 1,
                                          CurrencyType: 826
                                      })
        }


        return order_dto.to_json
      end

      def logger
        @logger ||= MarketplaceLogger.new
      end

      def subscribe_to(subscription_type)
        int_subscription_type = case subscription_type
          when :listing_created then 6
          else 0
        end

        json = {
          HookSubscriptionType: int_subscription_type,
          TargetUrl: 'http://' + Spree::Config.site_url + '/marketplace/listener/listing'
        }.to_json

        post_api_response('/api/hooks', '', json)
      end

      def post_api_response(endpoint_url, params = '', json = '')
        url = "#{@api_base_url}#{endpoint_url}?#{params}&apikey=#{@api_key}&accountkey=#{@account_key}"
        logger.info "Marketplace POST #{url} #{json}"

        response = ::HTTParty.post(url, verify: false, body: json, headers: {'Content-Type' => 'application/json'})
        logger.info "Marketplace POST response code=#{response.code} content-length=#{response.headers['content-length']}"

        return (response.code >= 200 || response.code < 300)
      end

      def get_api_response(endpoint_url, params = '', hash_result = false)
        separator = endpoint_url.index("?") == nil ? "?" : "&";

        url = "#{@api_base_url}#{endpoint_url}#{separator}#{params}&apikey=#{@api_key}&accountkey=#{@account_key}"
        logger.info "Marketplace GET #{url}"

        response = ::HTTParty.get(url, verify: false)
        logger.info "Marketplace GET response code=#{response.code} content-length=#{response.headers['content-length']}"

        return (hash_result ? convert_hash_to_ruby_style(response) : convert_array_to_ruby_style(response)) if response && response.code == 200
      end

      def convert_array_to_ruby_style(camel_case_arr)
        ruby_arr = []

        camel_case_arr.each do |arr_item|
          ruby_case_hash = {}
          arr_item.each_pair do |key, val|
            # if value is a Hash we convert keys to ruby_style
            val = convert_hash_to_ruby_style val if val.is_a? Hash

            # if value is an Array we iterate over it and change items
            if val.is_a? Array
              val.map! do |item|
                item = convert_hash_to_ruby_style item if item.is_a? Hash
              end
            end

            # add converted hash pair to new has
            ruby_case_hash.merge!({get_underscored_key(key) => val})
          end
          ruby_arr.push(ruby_case_hash)
        end
        ruby_arr
      end

      def convert_hash_to_ruby_style(camel_case_hash)
        ruby_case_hash = {}
        camel_case_hash.each_pair do |key, val|
          # if value is a Hash we convert keys to ruby_style
          val = convert_hash_to_ruby_style val if val.is_a? Hash

          # if value is an Array we iterate over it and change items
          if val.is_a? Array
            val.map! do |item|
              item = convert_hash_to_ruby_style item if item.is_a? Hash
            end
          end

          # add converted hash pair to new has
          ruby_case_hash.merge!({get_underscored_key(key) => val})
        end
        ruby_case_hash
      end

      def get_underscored_key(key)
        underscored_key = ActiveSupport::Inflector.underscore(key)
        underscored_key = underscored_key.downcase.tr(" ", "_")
      end
  end
end