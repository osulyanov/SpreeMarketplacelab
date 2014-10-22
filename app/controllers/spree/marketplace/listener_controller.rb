module Spree
  module Marketplace
    class ListenerController < Spree::Api::BaseController

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

        @result = "ok"

        order = Spree::Order.find_by!(number: store_order_id)

        # capture a payment, that would set shipment to ready state
        payment = order.payments[0]
        payment.capture!

        shipment = Spree::Shipment.find_by!(number: order.shipments[0].number)

        # if shipment.can_ready?
        #   shipment.ready!
          unless shipment.shipped?
            shipment.ship!
          end
        # else
        #   @result = "cant ready shipment"
        # end

      end
    end
  end
end