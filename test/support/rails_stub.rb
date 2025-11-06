$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))

require "pathname"

# Add .try method for test environment
class Object
  def try(method_name, *args, &block)
    if respond_to?(method_name)
      public_send(method_name, *args, &block)
    end
  end
end

module Rails
  class << self
    attr_accessor :root, :logger
  end

  module Env
    def self.to_s
      "test"
    end

    def self.development?
      false
    end
  end

  def self.env
    Env
  end

  def self.autoloaders
    @autoloaders ||= Autoloaders.new
  end

  class Autoloaders
    def initialize
      @main = Main.new
    end

    attr_reader :main

    class Main
      attr_reader :collapsed, :ignored

      def initialize
        @collapsed = []
        @ignored = []
      end

      def collapse(pattern)
        @collapsed << pattern
      end

      def ignore(pattern)
        @ignored << pattern
      end
    end
  end
end
