require 'base64'
require 'rexml/document'
=begin
@context = {
  tracking_numbers: [781158529725]
}
=end

module Logistics
  module Fedex
    class TrackShipment
      def initialize(context)
        @context = Hashie::Mash.new
        @request_params = Hashie::Mash.new context
        @context[:errors] = []
      end

      def track
        @fedex_tracking_numbers = @request_params.tracking_numbers

        begin
          validate_track_request_params
          track_shipment
        rescue => e
          errors = []
          if @context.errors.present?
            errors = @context.errors
            @context[:error_type] = :bad_request
          else
            errors << e.message
            @context[:error_type] = :internal_server_error
            @context[:errors] = errors
          end
          errors << @request_params.tracking_numbers.join(",")
          BizongoNotifier.alert(e, { params: errors })
        end
        @context
      end

      private

      def validate_track_request_params
        errors = []

        if @fedex_tracking_numbers.blank?
          errors << "Fedex Tracking Numbers not present"
        elsif @fedex_tracking_numbers.count > 30
          errors << "Enter less than 30 fedex tracking numbers"
        end

        unless errors.blank?
          @context[:errors] = errors
          raise ValidationError, @context.errors.join(",")
        end
      end

      def track_shipment
        track_shipment_response = Hashie::Mash.new(request_call.body)
        read_track_response track_shipment_response
      end

      def request_call
        client = Savon.client(
          :endpoint => APP_CONFIG['fedex']['fedex_track_url'],
          :namespace => "http://schemas.xmlsoap.org/soap/envelope/",
          :log => true,
          :log_level => :debug,
          :pretty_print_xml => true
        )
        client.call(:serviceAvailability, xml: track_body)
      end

      def read_track_response(track_shipment_response)
        if track_shipment_response.track_reply.highest_severity == "ERROR"
          read_create_shipment_error_notifications track_shipment_response.track_reply.notifications
        elsif @fedex_tracking_numbers.count == 1 &&
          track_shipment_response.track_reply.completed_track_details.duplicate_waybill &&
          track_shipment_response.track_reply.completed_track_details.duplicate_waybill == true
          @context[:tracking_details] = []

          track_shipment_response.track_reply.completed_track_details.track_details.each do |track_details|
            tracking_detail = Hashie::Mash.new
            tracking_detail[:tracking_number] = track_details.tracking_number
            tracking_detail[:status_detail] = track_details.status_detail
            tracking_detail[:package_count] = track_details.package_count
            tracking_detail[:package_sequence_number] = track_details.package_sequence_number
            tracking_detail[:destination_address] = track_details.destination_address
            @context[:tracking_details] << tracking_detail
          end
        elsif @fedex_tracking_numbers.count == 1 &&
          track_shipment_response.track_reply.completed_track_details.track_details.notification.severity == "ERROR"
          @context[:errors] << track_shipment_response.track_reply.completed_track_details.track_details.notification.localized_message
          @context[:error_type] = :bad_request
          raise ValidationError, @context.errors.join(",")
        else
          read_success_response track_shipment_response.track_reply
        end
      end

      def read_create_shipment_error_notifications(notifications)
        if notifications.class.to_s == "Array" || notifications.class.to_s == "Hashie::Array"
          read_error_notifications notifications
        else
          @context[:error_type] = :bad_request
          error_message = notifications.localized_message || notifications.message
          @context[:errors] << error_message
        end
        raise ValidationError, @context.errors.join(",")
      end

      def track_body
        @xml = "<soapenv:Envelope xmlns:soapenv='http://schemas.xmlsoap.org/soap/envelope/' xmlns:v8='http://fedex.com/ws/track/v8'>
                   <soapenv:Header />
                   <soapenv:Body>
                      <v8:TrackRequest>
                         <v8:WebAuthenticationDetail>
                            <v8:UserCredential>
                               <v8:Key>htmCAgo3GCO3U8Sl</v8:Key>
                               <v8:Password>knbu4OzugYY8r3fHPM7uAKEAv</v8:Password>
                            </v8:UserCredential>
                         </v8:WebAuthenticationDetail>
                         <v8:ClientDetail>
                            <v8:AccountNumber>911398206</v8:AccountNumber>
                            <v8:MeterNumber>252249125</v8:MeterNumber>
                         </v8:ClientDetail>
                         <v8:TransactionDetail>
                            <v8:CustomerTransactionId>Tracking</v8:CustomerTransactionId>
                         </v8:TransactionDetail>
                         <v8:Version>
                            <v8:ServiceId>trck</v8:ServiceId>
                            <v8:Major>8</v8:Major>
                            <v8:Intermediate>0</v8:Intermediate>
                            <v8:Minor>0</v8:Minor>
                         </v8:Version>
                         #{selection_details_xml}
                         <v8:ProcessingOptions>INCLUDE_DETAILED_SCANS</v8:ProcessingOptions>
                      </v8:TrackRequest>
                   </soapenv:Body>
                </soapenv:Envelope>"
      end

      def selection_details_xml
        selection_details = ""
        @fedex_tracking_numbers.each do |fedex_tracking_number|
          selection_details = selection_details +
            "<v8:SelectionDetails>
                <v8:CarrierCode>FDXE</v8:CarrierCode>
                <v8:PackageIdentifier>
                   <v8:Type>TRACKING_NUMBER_OR_DOORTAG</v8:Type>
                   <v8:Value>#{fedex_tracking_number}</v8:Value>
                </v8:PackageIdentifier>
              </v8:SelectionDetails>"
        end

        selection_details
      end

      def read_success_response(track_reply)
        completed_track_details = track_reply.completed_track_details
        if @fedex_tracking_numbers.count == 1 && completed_track_details.track_details
          @context[:tracking_details] = []
          tracking_details = Hashie::Mash.new
          tracking_details[:tracking_number] = completed_track_details.track_details.tracking_number
          tracking_details[:status_detail] = completed_track_details.track_details.status_detail
          tracking_details[:package_count] = completed_track_details.track_details.package_count
          tracking_details[:package_sequence_number] = completed_track_details.track_details.package_sequence_number
          tracking_details[:destination_address] = completed_track_details.track_details.destination_address
          get_tracking_events(completed_track_details.track_details.events, tracking_details) unless completed_track_details.track_details.events.blank?
          @context[:tracking_details] << tracking_details
        elsif @fedex_tracking_numbers.count > 1 && completed_track_details
          @context[:tracking_details] = []
          completed_track_details.each do |complete_track_detail|
            tracking_details = Hashie::Mash.new
            tracking_detail = complete_track_detail.track_details
            if complete_track_detail.duplicate_waybill && complete_track_detail.duplicate_waybill == true
              tracking_detail = tracking_detail[0]
            end
            tracking_details[:tracking_number] = tracking_detail.tracking_number

            tracking_details[:status_detail] = tracking_detail.status_detail
            tracking_details[:package_count] = tracking_detail.package_count
            tracking_details[:package_sequence_number] = tracking_detail.package_sequence_number
            tracking_details[:destination_address] = tracking_detail.destination_address
            get_tracking_events(tracking_detail.events, tracking_details) unless tracking_detail.events.blank?
            @context[:tracking_details] << tracking_details
          end
        else
          @context[:errors] = []
          @context[:errors] << "No tracking information available"
          @context[:error_type] = :bad_request
          raise ValidationError, @context.errors.join(",")
        end
      end

      def get_tracking_events(fedex_events, tracking_details)
        events = []
        if fedex_events.class.to_s == "Array" || fedex_events.class.to_s == "Hashie::Array"
          fedex_events.each do |fedex_event|
            event = generate_event(fedex_event)
            events << event
          end
        else
          event = generate_event(fedex_events)
          events << event
        end

        tracking_details[:events] = events
      end

      def generate_event(fedex_event)
        event = {}
        event[:timestamp] = fedex_event.timestamp.to_i
        event[:event_type] = fedex_event.event_type
        event[:event_description] = fedex_event.event_description
        event[:address] = fedex_event.address
        event[:arrival_location] = fedex_event.arrival_location
        event[:arrival_time] = fedex_event.timestamp.to_i * 1000 if fedex_event.timestamp.present?
        event
      end
    end
  end
end

