module Clients
  class Initialize
    def self.init
      ComponentTestSupport.recorder.record_init("Clients")
    end

    def self.ready
      ComponentTestSupport.recorder.record_ready("Clients")
    end
  end
end
