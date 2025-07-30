# lib/convert/weather/alert_base.rb
module Convert
  module Weather
    class AlertBase
      def self.call(_raw_data)
        raise NotImplementedError, "Subclasses must implement .call"
      end

      def self.standard_format(
        event:,
        headline:,
        description:,
        instruction:,
        status:,
        severity:,
        category:,
        certainty:,
        urgency:,
        onset:,
        effective:,
        expires:,
        ends:,
        sender:,
        sender_name:,
        message_type:,
        response:
      )
        {
          event: event,
          headline: headline,
          description: description,
          instruction: instruction,
          status: status,
          severity: severity,
          category: category,
          certainty: certainty,
          urgency: urgency,
          onset: onset,
          effective: effective,
          expires: expires,
          ends: ends,
          sender_name: sender_name,
          sender: sender,
          message_type: message_type,
          response: response
        }
      end
    end
  end
end
