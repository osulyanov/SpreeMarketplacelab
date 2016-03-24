require 'httparty'

module Marketplace
  class Api
    include Listenable

    def initialize(api_key, account_key, api_base_url, spree_auth_token, mark_orders_as_awaiting_dispatch)
      @api_key = api_key
      @account_key = account_key
      @api_base_url = api_base_url
      @spree_auth_token = spree_auth_token
      @mark_orders_as_awaiting_dispatch = mark_orders_as_awaiting_dispatch

      @api_version = "api" # could be "api/v1"
      @appName = ((ENV["MARKETPLACE_APP_NAME"]) || "Spree-NulAppName")

      # marketplacelab headers
      @headers = {
        "X-MarketplaceLab-User-Agent-Application-Name" => @appName,
        "X-MarketplaceLab-User-Agent-Language" => "Ruby #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}",
        "X-MarketplaceLab-User-Agent-Application-Version" => "master"
      }

    end

    def self.instance
      @instance ||= begin
        api_key = SpreeMarketplacelab::Config[:apiKey]
        account_key = SpreeMarketplacelab::Config[:accountKey]
        api_base_url = SpreeMarketplacelab::Config[:apiBaseUrl]
        spree_auth_token = SpreeMarketplacelab::Config[:authToken]
        mark_orders_as_awaiting_dispatch = SpreeMarketplacelab::Config[:markOrderAsAwaitingDispatchOnCreate]

        self.new(api_key, account_key, api_base_url, spree_auth_token, mark_orders_as_awaiting_dispatch)
      end
    end

    # creates or updates a product in spree
    # returns [spree_product, is_new_product_created]
    #   spree_product -- a reference to a product
    #   is_new_product_created -- boolean, would be true in case a new product was just created
    def create_or_update_product(store_product_id, price)
      s = ::Stopwatch.new

      tmpl_products = get_products(store_product_id)

      if tmpl_products == nil || tmpl_products.length == 0
        logger.error "Products fro SKU #{store_product_id} not found at the marketplace"
        return nil
      end

      marketplace_product = tmpl_products[0]

      logger.info "TMPL call finished, took #{s.elapsed_time}"

      spree_product = Spree::Product.eager_load(:taxons).eager_load(:master).eager_load(:variant_images).find_by("spree_variants.sku = ?", store_product_id)

      logger.info "Spree product read, took #{s.elapsed_time}"

      is_new_product_created = false

      if spree_product == nil
        price = 0.0 if price.nil?

        logger.info "Product for SKU #{store_product_id} not found in spree, creating a new one, took #{s.elapsed_time}"

        # create new product (see spree_api products_controller)
        product_params = {
          shipping_category_id: 1,
          name: marketplace_product["title"],
          price: price,
          sku: marketplace_product["store_product_id"],
          description: marketplace_product["long_description"],
          weight: marketplace_product["weight_in_grams"],
          height: marketplace_product["height_in_mm"],
          width: marketplace_product["width_in_mm"],
          depth: marketplace_product["depth_in_mm"],
        }

        options = { variants_attrs: [], options_attrs: [] }
        spree_product = Spree::Core::Importer::Product.new(nil, product_params, options).create
        is_new_product_created = true
      else
        logger.info "Product for SKU #{store_product_id} found in spree, updating, took #{s.elapsed_time}"

        spree_product.name = marketplace_product["title"]

        if price != nil
          spree_product.price = price
        end

        spree_product.description = marketplace_product["long_description"]
        spree_product.weight = marketplace_product["weight_in_grams"]
        spree_product.height = marketplace_product["height_in_mm"]
        spree_product.width = marketplace_product["width_in_mm"]
        spree_product.depth = marketplace_product["depth_in_mm"]
      end

      create_or_update_product_images(spree_product, marketplace_product)

      logger.info "Product saved, SKU: #{store_product_id}, took #{s.elapsed_time}"

      is_ingredients_present = spree_product.has_attribute?(:ingredients)

      if marketplace_product['attributes'] != nil
        properties = {}
        marketplace_product['attributes'].each do |attr|
          properties[attr['name']] = [] unless properties[attr['name']].present?
          properties[attr['name']] << attr['value']
        end
        properties.each do |name, values|
          if is_ingredients_present && name == 'Ingredients'
            spree_product.ingredients = values.join(', ')
          else
            spree_product.set_property(name, values.join(', ').truncate(250, omission: '...'))
          end
        end
      end

      spree_product.save!

      logger.info "Properties set, returning, SKU: #{store_product_id}, took #{s.elapsed_time}"

      return spree_product, is_new_product_created
    end

    def create_or_update_product_images(spree_product, marketplace_product)

      if marketplace_product["images"] == nil
        return
      end

      # if spree_product.images == nil
      #   spree_product.images
      # end

      file_names = spree_product.images.pluck(:attachment_file_name)

      marketplace_product["images"].each { |tmpl_img|
        tmpl_uri = URI.parse(tmpl_img["image_url"])

        if tmpl_uri == nil || tmpl_uri.scheme == nil
          logger.warn "Incorrect image url: #{tmpl_img["image_url"]}, spree product id: #{spree_product.id}, tmpl store product id: #{marketplace_product["store_product_id"]}"
          next
        end

        tmpl_file_name = File.basename(tmpl_uri.path)

        if !file_names.include? tmpl_file_name
          begin
            image = Spree::Image.create!({ :attachment => tmpl_uri, :viewable => spree_product })
            spree_product.images << image
          rescue
            logger.warn "Error adding image to spree, image url: #{tmpl_img["image_url"]}, spree product id: #{spree_product.id}, tmpl store product id: #{marketplace_product["store_product_id"]}"
          end
        end
      }
    end

    def generate_store_product_id marketplace_id
      "marketplace_#{marketplace_id}"
    end

    def put_product_spi(marketplace_id, store_product_id)
      put_api_response("/products", "marketplaceId=#{marketplace_id}&storeProductId=#{store_product_id}", false)
    end

    def get_product_categories(store_product_id)
      get_api_response("/products/#{store_product_id}/categories", "", false)
    end

    def get_products(store_product_ids)
      get_api_response("/products/#{store_product_ids}", "", false)
    end

    def get_product_by_marketplace_id(marketplace_id)
      get_api_response("/products/", "marketplaceId=#{marketplace_id}", true)
    end

    def get_seller_by_username(seller_username)
      get_api_response("/sellers", "userName=#{CGI.escape(seller_username)}", true)
    end

    def get_seller_by_alias(seller_alias)
      get_api_response("/sellers", "alias=#{CGI.escape(seller_alias)}", true)
    end

    def get_seller(seller_id)
      get_api_response("/sellers/#{seller_id}", "", true)
    end

    def put_seller(seller_data)
      put_api_response("/sellers", "", seller_data.to_json, true)
    end

    def post_seller(seller_id, data)
      post_api_response("/sellers/#{seller_id}", "", data.to_json, true)
    end

    def post_seller_verify(seller_id, verification_token)
      post_api_response("/sellers/#{seller_id}/verify", "", { 'SellerVerificationToken' => verification_token }.to_json)
    end

    def check_stock(store_product_id)
      get_api_response("/listings/#{store_product_id}/availablestock", "", false)
    end

    def close_listing(listing_id)
      data = { "ListingStatus" => "Closed", "ListingId" => listing_id }.to_json
      post_api_response("/listings/#{listing_id}", "", data, true)
    end

    def open_listing(listing_id)
      data = { "ListingStatus" => "Open", "ListingId" => listing_id }.to_json
      post_api_response("/listings/#{listing_id}", "", data, true)
    end

    def reject_listing(listing_id)
      data = { "ListingStatus" => "Rejected", "ListingId" => listing_id }.to_json
      post_api_response("/listings/#{listing_id}", "", data, true)
    end

    def update_listing(listing_id, listing_data)
      post_api_response("/listings/#{listing_id}", "", listing_data.to_json, true)
    end

    def sellers_listings(seller_id, params="")
      get_api_response("/sellers/#{seller_id}/listings", params, false)
    end

    def post_sellers_listing(seller_id, listing_data)
      post_api_response("/listings/seller/#{seller_id}", "", listing_data.to_json, true)
    end

    def get_order(order_id)
      get_api_response("/orders/#{order_id}", "", true)
    end

    def get_sellers_account(seller_id, account_id)
      get_api_response("/sellers/#{seller_id}/account/#{account_id}", "", true)
    end

    def put_sellers_account(seller_id, data)
      put_api_response("/sellers/#{seller_id}/account", "", data.to_json, true)
    end

    def get_sellers_orders(seller_id, params = "")
      get_api_response("/sellers/#{seller_id}/orders", params, true)
    end

    def get_craft_product(store_product_id)
      get_api_response("/products/#{store_product_id}/craftlisting", "", true)
    end

    def dispatch_order(store_order_id, store_carrier_id, tracking_number)
      dispatch_model = {
        StoreOrderId: store_order_id,
        DispatchDate: Time.now.strftime("%Y-%m-%d %H:%M"),
      }
      dispatch_model[:StoreCarrierId] = store_carrier_id if store_carrier_id.present?
      dispatch_model[:TrackingNumber] = tracking_number if tracking_number.present?
      spree_order = Spree::Order.find_by(number: store_order_id)
      dispatch_model[:ShippingType] = get_shipping_type(spree_order, spree_order.line_items.first) if spree_order

      post_api_response("/orders/#{store_order_id}/dispatch", "", dispatch_model.to_json)
    end

    def get_dispatch_status(store_product_id)
      get_api_response("/orders/dispatchstatus", "storeProductId=#{store_product_id}", true)
    end

    def get_orderitem_dispatch_status(store_order_id, store_product_id)
      get_api_response("/orders/#{store_order_id}/orderitems/#{store_product_id}", "", true)
    end

    def get_product_attributes(product_type_id)
      get_api_response("/producttypes/#{product_type_id}", "", true)
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

      post_api_response("/listings/selleremail", "sellerEmail=#{spree_user.email}", listing_model)
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

      post_api_response('/products', '', marketplace_product_json)
    end

    def update_product(spree_product)
      create_product(spree_product)
    end

    def get_best_prices(product_ids)
      get_api_response("/products/#{product_ids}/listings?condition=new&view=bestprices")
    end

    def create_order(spree_order, charge_id=nil)
      marketplace_order_json = convert_to_marketplace_order(spree_order, charge_id)
      @mark_orders_as_awaiting_dispatch = 'true'
      post_api_response('/orders/create', 'markAsDispatched=' + @mark_orders_as_awaiting_dispatch.to_s, marketplace_order_json)
    end

    def cancel_order(spree_order)
      marketplace_order_adjustment = convert_to_order_adjustment(spree_order, 'Cancelled')
      post_api_response('/' + spree_order.number + '/adjustment', '', marketplace_order_adjustment)
    end

    def cancel_ml_order(order, reason)
      data = {
        "StoreOrderId" => order['store_order_id'],
        "OrderAcknowledgementStatus" => 3,
        "FailureReason" => reason
      }.to_json
      post_api_response("/sellers/#{order['order_items'][0]['seller_id']}/orders/#{order['store_order_id']}/acknowledge", '', data, true)
    end

    def cancel_ml_order_v2(order, reason)
      data = {
        "StoreOrderId" => order['store_order_id'],
        "Adjustments" => [
          {
            "StoreOrderItemId" => order['order_items'][0]['store_order_item_id'],
            "Quantity" => order['order_items'][0]['quantity'],
            "AdjustmentType" => 20, # seller cancellation
            "AdjustmentReasonCode" => "sco", # "Other" seller cancellation reason
            "AdjustmentReasonFreeText" => reason,
            "Currency" => order['order_items'][0]['currency_type'],
            "Amount" => order['order_items'][0]['price']
          }
        ]
      }.to_json

      post_api_response("/orders/#{order['store_order_id']}/adjustments", '', data, true)
    end

    def notify(event_name, *args)
      notify_listeners(event_name, *args)
    end

    # @listing_ids comma separated list of listings identifiers
    def get_deliveryoptions(listing_ids, country_code)
      get_api_response("/listings/#{listing_ids}/shippingmethods/#{country_code}")
    end

    # get listings for a product(s)
    # @product_ids comma separated list of product identifiers
    def get_listings(product_ids)
      get_api_response("/products/#{product_ids}/listings")
    end

    def get_listing(listing_id)
      listing = get_api_response("/listings/#{listing_id}")
      listing[0] if listing && listing.any?
    end

    def get_carriers
      get_api_response("/carriers")
    end

    def subscribe_to_webhooks
      subscribe_to :listing_created
      subscribe_to :listing_updated
      subscribe_to :product_created
      subscribe_to :product_updated
      subscribe_to :order_allocated
      subscribe_to :order_dispatched
      subscribe_to :order_unable_to_dispatch
      subscribe_to :order_awaiting_dispatch
    end

    private

    # some marketplacelab constants
    COUNTRY_ID_UK = 235 # country United Kingdom
    LISTING_CONDITION_ID_NEW = 1 # listing condition New
    QUANTITY_UNIT_TYPE_ID = 1 # quantity unit type Item
    CURRENCY_TYPE_ID_GBP = 826 # currency type GBP
    PAYMENT_STATUS_PAID = 30 # payment status Paid
    SHIPPING_STATUS_PENDING = 10 # shipping status Pending

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

    def convert_to_marketplace_order(spree_order, charge_id)
      order_dto = {
        StoreOrderId: spree_order.number,
        SellerOrderId: spree_order.number,
        CustomerEmail: spree_order.email,
        CustomerPhoneNumber: spree_order.billing_address.phone,
        CustomerTitle: "",
        CustomerFirstName: spree_order.billing_address.firstname,
        CustomerLastName: spree_order.billing_address.lastname,
        StoreOrderDate: (spree_order.completed_at || Time.zone.now),
      }

      order_dto[:OrderItems] = []
      order_dto[:OrderItemGroupModels] = []

      spree_order.shipments.each do |shipment|
        items_in_shipment = shipment.line_items.size

        shipment.line_items.each do |item|
          if item.respond_to?(:listing)
            listing = item.listing
          else
            listing_id = Spree::Variant.joins(:product).find_by("spree_variants.id=?", item.variant_id).product.property("ListingId")
            listing = get_listing(listing_id)
          end

          order_dto[:OrderItems].push({
                                        ListingId: listing['listing_id'] || listing[:listing_id],
                                        PaymentStatus: PAYMENT_STATUS_PAID,
                                        ShippingStatus: SHIPPING_STATUS_PENDING,
                                        Quantity: item.quantity,
                                        Price: item.try(:price_for_ml) || item.price,
                                        StoreOrderItemId: spree_order.number + "-" + item.id.to_s,
                                        StoreProductId: item.variant.sku,
                                        SellerId: listing['seller_id'] || listing[:seller_id],
                                        ListingDispatchFromCountryId: COUNTRY_ID_UK,
                                        ListingConditionId: LISTING_CONDITION_ID_NEW,
                                        QuantityUnitTypeId: QUANTITY_UNIT_TYPE_ID,
                                        CurrencyType: CURRENCY_TYPE_ID_GBP,
                                        DeliveryName: spree_order.shipping_address.firstname + " " + spree_order.shipping_address.lastname,
                                        DeliveryAddress1: spree_order.shipping_address.address1,
                                        DeliveryAddress2: spree_order.shipping_address.address2,
                                        DeliveryCountry: spree_order.shipping_address.country.iso,
                                        DeliveryCounty: spree_order.shipping_address.state_name,
                                        DeliveryTown: spree_order.shipping_address.city,
                                        DeliveryPostcode: spree_order.shipping_address.zipcode,
                                        DeliveryCost: get_delivery_cost(spree_order, item) / items_in_shipment.to_f,
                                        ShippingType: get_shipping_type(spree_order, item)
                                      })
          if charge_id
            order_dto[:OrderItemGroupModels].push({
                                                    StoreOrderItemIds: [spree_order.number + "-" + item.id.to_s],
                                                    OptionTypeModels: [
                                                      {
                                                        StoreOptionTypeId: "StripeChargeId",
                                                        OptionDetailModels: [
                                                          {
                                                            Key: "StripeChargeId",
                                                            Value: charge_id
                                                          }
                                                        ]
                                                      }
                                                    ]
                                                  })
          end

        end
      end

      return order_dto.to_json
    end

    def get_delivery_cost(spree_order, order_item)
      selected_shipment = nil
      spree_order.shipments.each do |shipment|
        shipment.inventory_units.each do |inventory_unit|
          if inventory_unit.line_item == order_item
            selected_shipment = shipment
          end
        end
      end

      return 0 if selected_shipment.nil?

      shipping_method = nil
      selected_shipment.shipping_rates.each do |rate|
        if rate.selected
          return rate.cost
        end
      end

      return 0
    end

    def get_shipping_type(spree_order, order_item)
      selected_shipment = nil
      spree_order.shipments.each do |shipment|
        shipment.inventory_units.each do |inventory_unit|
          if inventory_unit.line_item == order_item
            selected_shipment = shipment
          end
        end
      end

      return nil if selected_shipment.nil?

      shipping_method = nil
      selected_shipment.shipping_rates.each do |rate|
        if rate.selected
          shipping_method = rate.shipping_method
        end
      end

      if shipping_method != nil
        return /(\d+)/.match(shipping_method.admin_name)[0].to_i
      end
    end

    def logger
      @logger ||= MarketplaceLogger.new
    end

    def subscribe_to(subscription_type)
      if subscription_type == :listing_created then
        payload = {
          HookSubscriptionType: 6,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/listing?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :listing_updated then
        payload = {
          HookSubscriptionType: 7,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/listing?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :product_created then
        payload = {
          HookSubscriptionType: 10,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/product?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :product_updated then
        payload = {
          HookSubscriptionType: 11,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/product?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :order_allocated then
        payload = {
          HookSubscriptionType: 2,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/order?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :order_dispatched then
        payload = {
          HookSubscriptionType: 5,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/order_dispatched?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :order_unable_to_dispatch then
        payload = {
          HookSubscriptionType: 13,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/order_unable_to_dispatch?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      if subscription_type == :order_awaiting_dispatch then
        payload = {
          HookSubscriptionType: 14,
          TargetUrl: 'https://' + Spree::Config.site_url + '/marketplace/listener/order_awaiting_dispatch?token=' + @spree_auth_token
        }.to_json
        api_hooks_url = '/hooks'
      end

      post_api_response(api_hooks_url, '', payload)
    end

    def put_api_response(endpoint_url, params = '', json = '', return_response = false)
      if params != ''
        params += "&"
      end

      params += "apikey=#{@api_key}&accountkey=#{@account_key}"

      url = "#{@api_base_url}#{@api_version}#{endpoint_url}?#{params}"
      logger.info "Marketplace PUT #{url} #{json}"

      headers = @headers
      headers["Content-Type"] = "application/json"

      s = ::Stopwatch.new
      response = ::HTTParty.put(url, verify: false, body: json, headers: headers)
      logger.info "Marketplace PUT response code=#{response.code} content-length=#{response.headers['content-length']}, took #{s.elapsed_time}"

      success = response.code >= 200 && response.code < 300

      if return_response
        return success, response.parsed_response
      else
        success
      end
    end

    def post_api_response(endpoint_url, params = '', json = '', return_response = false)
      if params != ''
        params += "&"
      end

      params += "apikey=#{@api_key}&accountkey=#{@account_key}"

      url = "#{@api_base_url}#{@api_version}#{endpoint_url}?#{params}"
      logger.info "Marketplace POST #{url} #{json}"

      headers = @headers
      headers["Content-Type"] = "application/json"

      s = ::Stopwatch.new
      response = ::HTTParty.post(url, verify: false, body: json, headers: headers)
      logger.info "Marketplace POST response code=#{response.code} content-length=#{response.headers['content-length']}, took #{s.elapsed_time}"

      success = response.code >= 200 && response.code < 300

      if return_response
        return success, response.parsed_response
      else
        success
      end
    end

    def get_api_response(endpoint_url, params = '', hash_result = false)
      if params != ''
        params += "&"
      end

      params += "apikey=#{@api_key}&accountkey=#{@account_key}"

      url = "#{@api_base_url}#{@api_version}#{endpoint_url}?#{params}"
      logger.info "Marketplace GET #{url}"

      s = ::Stopwatch.new
      response = ::HTTParty.get(url, verify: false, headers: @headers)
      logger.info "Marketplace GET response code=#{response.code} content-length=#{response.headers['content-length']}, took #{s.elapsed_time}"

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
          ruby_case_hash.merge!({ get_underscored_key(key) => val })
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
        ruby_case_hash.merge!({ get_underscored_key(key) => val })
      end
      ruby_case_hash
    end

    def get_underscored_key(key)
      underscored_key = ActiveSupport::Inflector.underscore(key)
      underscored_key = underscored_key.downcase.tr(" ", "_")
    end
  end
end
