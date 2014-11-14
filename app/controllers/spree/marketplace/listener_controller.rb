module Spree
  module Marketplace
    class ListenerController < Spree::Api::BaseController

      def logger
        @logger ||= MarketplaceLogger.new
      end

      # TMPL Hook calls this on listing create event
      def listing
        listing_id = request.POST["ListingId"]

        marketplace_api = ::Marketplace::Api.instance
        listing = marketplace_api.get_listing(listing_id)

        marketplace_api.notify(:listing_created, listing)

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
    end
  end
end