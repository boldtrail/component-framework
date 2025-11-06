require "test_helper"

class FrameworkTest < Minitest::Test
  include ComponentTestSupport

  def setup
    reset_recorder!

    # Set Rails.root to point to test directory so components_base_dir finds test/components
    @original_rails_root = Rails.root
    Rails.root = Pathname.new(__dir__)

    reset_framework_state
  end

  def teardown
    cleanup_component_constants
    reset_framework_state
    Rails.root = @original_rails_root
  end

  def test_get_components_discovers_nested_components
    names = Component::Framework.get_components.map { |info| info[:name] }
    assert_equal ["Clients", "Clients::Billing"], names
  end

  def test_get_component_modules_defines_nested_components
    modules = Component::Framework.get_component_modules
    assert_includes modules, Clients
    assert_includes modules, Clients::Billing
  end

  def test_initialize_runs_component_initializers
    app = ComponentTestSupport::FakeApplication.new
    Component::Framework.initialize(app, verbose: false)

    app.run_initializers
    app.run_after_initialize

    assert_equal ["Clients", "Clients::Billing"].sort, ComponentTestSupport.recorder.init_calls.sort
    assert_equal ["Clients", "Clients::Billing"].sort, ComponentTestSupport.recorder.ready_calls.sort
  end
end
