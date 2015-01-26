module Spree
  module Marketplace
    class ListenerController < Spree::Api::BaseController

      def product
        product_sku = request.POST["StoreProductId"]
        marketplace_api = ::Marketplace::Api.instance

        logger.info "Product hook for SKU: #{product_sku}"

        tmpl_products = marketplace_api.get_products(product_sku)

        if tmpl_products == nil || tmpl_products.length == 0
          logger.error "Products fro SKU #{product_sku} not found at the marketplace"
          return
        end

        marketplace_product = tmpl_products[0]
        price = request.POST['Price']['Amount'].to_f if request.POST['Price'] != nil

        spree_product = Spree::Product.includes(:taxons).includes(:master).joins(:master).find_by("spree_variants.sku = ?", product_sku)

        if spree_product == nil
          logger.info "Product for SKU #{product_sku} not found in spree, creating a new one"

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

        else
          logger.info "Product for SKU #{product_sku} found in spree, updating"

          spree_product.name = marketplace_product["title"]
          spree_product.price = price
          spree_product.description = marketplace_product["long_description"]
          spree_product.weight = marketplace_product["weight_in_grams"]
          spree_product.height = marketplace_product["height_in_mm"]
          spree_product.width = marketplace_product["width_in_mm"]
          spree_product.depth = marketplace_product["depth_in_mm"]
        end

        spree_product.save!
        logger.info "Product saved, SKU: #{product_sku}"

        if marketplace_product['attributes'] != nil
          marketplace_product['attributes'].each do |attr|
            spree_product.set_property(attr['name'], attr['value'])
          end
        end

        marketplace_api.notify(:product_updated, product_sku)

        @result = "ok"
      end

      def listing
        # listing_id = request.POST["ListingId"]
        product_sku = request.POST["StoreProductId"]

        logger.info "Listing hook for SKU: #{product_sku}"

        marketplace_api = ::Marketplace::Api.instance
        marketplace_api.notify(:listing_updated, product_sku)

        @result = "ok"
      end

      def order
        store_order_id = request.POST["StoreOrderId"]

        order = Spree::Order.find_by!(number: store_order_id)

        @result = "ok"
      end

      def order_dispatched
        store_order_id = request.POST["StoreOrderId"]
        logger.info "Order Dispatched Hook called for StoreOrderId " + store_order_id + " ."
        @result = "ok"

        order = Spree::Order.find_by!(number: store_order_id)


        if @order

        end

        # capture a payment, that would set shipment to ready state
        # Loop through the payments and find one at the correct status
        processed = false;
        order.payments.each do |payment|
          if payment.state == 'pending'
            payment.capture!
            processed = true
            logger.info "Successully captured payment for StoreOrderId " + store_order_id
            break;
          end
        end

        if processed
          # If we successfully proccessed the payment then Ship the order!
          shipment = Spree::Shipment.find_by!(number: order.shipments[0].number)
          unless shipment.shipped?
            shipment.ship!
            logger.info "Successfully shipped StoreOrderId " + store_order_id
          else
            logger.error "Failed to ship StoreOrderId " + store_order_id + " but payment has been taken and udpated. ** this will need to be fixed manually."
          end
        else
            logger.error "Failed to find a pending status payment to capture for StoreOrderId : " + store_order_id + " - ** this will need to be fixing manually."
        end

      end

      private
        def logger
          @logger ||= MarketplaceLogger.new
        end

    end
  end
end