require_relative "rails_stub"

module ComponentTestSupport
  module_function

  def recorder
    Recorder
  end

  def reset_recorder!
    Recorder.reset!
  end

  def reset_framework_state
    Component::Framework.instance_variable_set(:@base_dir, nil)
    Component::Framework.instance_variable_set(:@get_components, nil)
  end

  def cleanup_component_constants
    return unless Object.const_defined?(:Clients)

    Clients.send(:remove_const, :Billing) if Clients.const_defined?(:Billing, false)
    Object.send(:remove_const, :Clients)
  end

  class Recorder
    class << self
      attr_reader :init_calls, :ready_calls

      def reset!
        @init_calls = []
        @ready_calls = []
      end

      def record_init(name)
        @init_calls << name
      end

      def record_ready(name)
        @ready_calls << name
      end
    end
  end

  class FakeApplication
    attr_reader :config, :reloader

    def initialize
      @config = FakeConfig.new
      @initializer_blocks = []
      @reloader = FakeReloader.new
    end

    def initializer(_name, group:, &block)
      @initializer_blocks << block
    end

    def run_initializers
      @initializer_blocks.each { |block| block.call(self) }
    end

    def run_after_initialize
      @config.run_after_initialize(self)
    end

    class FakeConfig
      attr_accessor :autoload_paths, :eager_load_paths
      attr_reader :paths

      def initialize
        @autoload_paths = []
        @eager_load_paths = []
        @paths = Hash.new { |hash, key| hash[key] = FakePath.new }
        @after_initialize_blocks = []
      end

      def after_initialize(&block)
        @after_initialize_blocks << block
      end

      def run_after_initialize(app)
        @after_initialize_blocks.each { |block| block.call(app) }
      end

      class FakePath
        attr_reader :entries

        def initialize
          @entries = []
        end

        def push(path)
          @entries << path
        end

        def unshift(*paths)
          @entries = paths + @entries
        end
      end
    end

    class FakeReloader
      def before_class_unload
      end

      def to_prepare
      end
    end
  end
end
