module Spree
  module Marketplace
    class ListenerController < Spree::Api::BaseController
      skip_before_filter :authenticate_user

      def product
        product_sku = request.POST["StoreProductId"]
        marketplace_api = ::Marketplace::Api.instance

        logger.info "Product hook for SKU: #{product_sku}"

        stopwatch = ::Stopwatch.new

        price = request.POST['Price']['Amount'].to_f unless price.nil?
        # price = 0.0 if price.nil?

        if product_sku.blank?
          marketplace_id = request.POST["MarketplaceId"]
          product_sku = marketplace_api.generate_store_product_id marketplace_id
          result = marketplace_api.put_product_spi marketplace_id, product_sku
          logger.info "result=#{result.inspect}"
        end

        spree_product = marketplace_api.create_or_update_product(product_sku, price)

        if spree_product != nil
          marketplace_api.notify(:product_updated, product_sku)
        end

        logger.info "Product hook for SKU: #{product_sku} processed, took #{stopwatch.elapsed_time}"

        @result = "ok"
      end

      def listing
        # listing_id = request.POST["ListingId"]
        product_sku = request.POST["StoreProductId"]

        logger.info "Listing hook for SKU: #{product_sku}"

        stopwatch = ::Stopwatch.new

        marketplace_api = ::Marketplace::Api.instance
        marketplace_api.notify(:listing_updated, product_sku)

        logger.info "Listing hook for SKU: #{product_sku} processed, took #{stopwatch.elapsed_time}"

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

        marketplace_api = ::Marketplace::Api.instance
        marketplace_api.notify(:order_dispatched, request.POST["StoreOrderId"], request.POST["StoreOrderItemIds"])
      end

      def order_unable_to_dispatch
        store_order_id = request.POST["StoreOrderId"]
        logger.info "Order Unable To Dispatch Hook called for StoreOrderId #{store_order_id}."
        @result = "ok"

        order = Spree::Order.find_by!(number: store_order_id)

        if order
          order.cancel!
          logger.info "Successfully cancelled an order, StoreOrderId #{store_order_id}."
        else
          logger.error "Order not found, StoreOrderId #{store_order_id}."
        end
      end

      def order_awaiting_dispatch
        store_order_id = request.POST["StoreOrderId"]
        logger.info "Order Awaiting Dispatch called for StoreOrderId " + store_order_id + " ."
        logger.warn "request.POST=#{request.POST.inspect}"

        marketplace_api = ::Marketplace::Api.instance
        marketplace_api.notify(:awaiting_dispatch, store_order_id)

        @result = "ok"
      end

      private
      def logger
        @logger ||= MarketplaceLogger.new
      end
    end
  end
end