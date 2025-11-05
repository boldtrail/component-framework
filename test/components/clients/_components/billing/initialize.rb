module Clients
  module Billing
    class Initialize
      def self.init
        ComponentTestSupport.recorder.record_init("Clients::Billing")
      end

      def self.ready
        ComponentTestSupport.recorder.record_ready("Clients::Billing")
      end
    end
  end
end
