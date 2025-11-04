require "active_support/inflector"
require "component/framework/version"
require "component/settings"

module Component
  module Framework

    # Components root folder path
    #
    # @return [string] Components root folder path
    def self.components_base_dir
      @base_dir ||= Rails.root.join("components")
    end


    # Initialize Component Framework
    #
    # @param application [Rails::Application] the application class
    # @param verbose [bool] allows to show components initialization log, default `false`
    def self.initialize(application, verbose: false)
      @verbose = verbose

      log("Components Initialization Started")
      log("Components Path: #{components_base_dir}")

      # Do not use "_components" folder as a part of class namespace, so file like:
      # components/clients/_components/jon_doe/core/my_class.rb will define a class name:
      # Clients::JonDoe::MyClass
      Rails.autoloaders.main.collapse("components/*/_components")

      # Instruct autoloader not to load route files, they will be loaded by rails automatically
      Rails.autoloaders.main.ignore("#{components_base_dir}/**/routes.rb")

      # add eager and autoload path that will allow to eager load and resolve components with namespaces.
      application.config.autoload_paths += [components_base_dir.to_s]
      application.config.eager_load_paths += [components_base_dir.to_s]

      log("Discovered Components: #{get_components.map { |c| c[:name] }.join(", ")}")

      log("Register DB Migrations")
      _get_component_migrations_paths.each { |path| application.config.paths["db/migrate"].push(path) }

      log("Register Components Routes")
      application.config.paths["config/routes.rb"].unshift(*_get_component_routing_paths)

      log("Register Components Helpers")
      application.config.paths["app/helpers"].unshift(*_get_component_helpers_paths)
      application.config.autoload_paths += _get_component_helpers_paths

      # Register legacy directories under modules
      log("Register legacy directories under modules")
      get_components.each do |component_info|
        # "_legacy_models" is a special sub directory under each component that is added to load paths so it can have
        # classes without namespaces. File in components/clients/_legacy_models/client.rb will define class "Client"
        legacy_dir_path = component_info[:path] + "/_legacy_models"
        if Dir.exist?(legacy_dir_path)
          application.config.autoload_paths << legacy_dir_path
          application.config.eager_load_paths << legacy_dir_path
        end
      end

      # Initialize components
      #
      # Initialization happen in 2 steps to allow components to perform actions upon initialized components.
      # First cycle is a part of Rails initialization, so it's possible to configure Rails env in it
      # like registering middleware etc.
      application.initializer :initialize_components, group: :all do |app|
        components = Component::Framework.get_component_modules(load_initializers: true)
        Component::Framework.log("Initialize Components")
        components.each do |component|
          if component.const_defined?(:Initialize)
            component.const_get(:Initialize).try(:init)
          end
        end
      end

      # Post initialization of components
      # when all the other parts are ready to be referenced
      #
      # A place to register subscribers as well as call other component's services.
      application.config.after_initialize do |app|
        components = get_component_modules

        log("Post-Initialize Components")
        components.each do |component|
          if component.const_defined?(:Initialize)
            component.const_get(:Initialize).try(:ready)
          end
        end

        log("Components Initialization Done")
      end

      if Rails.env.development?
        # In development we use Autoreload Rails feature
        # it will "unload" all classes/constants on any code change
        # this leads to breaking all cross-component initialization logic (e.g. changes subscriptions will be lost)
        # so we reinitialize components in case autoreload happened

        # "to_prepare" callback may run multiple times during single code reload,
        # we use "initialized" variable to ensure we run initializers only once after reach unload
        initialized = true

        application.reloader.before_class_unload do
          initialized = false
        end

        application.reloader.to_prepare do
          next if initialized

          components = Component::Framework.get_components.reject { |c| c[:name] == "Tracing" }
          initializers = components.filter_map { |component| Component::Framework.load_initializer(component) }

          # Re-run initializers
          initializers&.each { |initializer| initializer.init if initializer.respond_to?(:init) }
          initializers&.each { |initializer| initializer.ready if initializer.respond_to?(:ready) }

          initialized = true
        end
      end

      log("Configuration Finished")
    end


    # List of components
    def self.get_components
      directories = Dir["#{components_base_dir}/*"] + Dir["#{components_base_dir}/**/_components/*"]
      @get_components ||= directories.sort.map do |full_path|
        # Get name with module ("Accounting", "Accounting::Taxes", etc)
        name = full_path.sub("#{components_base_dir}/", "").gsub("/_components", "").camelize
        {
          name: name,
          path: full_path
        }
      end
    end


    # List of component root modules
    # @param load_initializers [bool] force component initialize.rb load
    # @return [Array<Object>] List of component root modules
    def self.get_component_modules(load_initializers: false)
      components = get_components

      components.each { |component_info| _define_component_module(component_info[:name]) }

      if load_initializers
        Component::Framework.log("Load Components Initializers")
        components.each { |component_info| load_initializer(component_info) }
      end

      components.map { |component| component_module_by_name(component[:name]) }
    end


    # Get the component root module by component name
    #
    # @param name [string] the component name
    # @return [Object] Component root module
    def self.component_module_by_name(name)
      return name.camelize.constantize
    rescue NameError, ArgumentError
      message = "Component #{name} not found"
      log(message)
      raise ComponentNotFoundError, message
    end


    def self.load_initializer(component_info)
      initializer_path = component_info[:path] + "/initialize.rb"
      return if !File.exist?(initializer_path)

      # Ensure we have component root defined
      _define_component_module(component_info[:name])

      require initializer_path

      initializer_name = "#{component_info[:name]}::Initialize"
      if !Object.const_defined?(initializer_name)
        raise "Initializer at '#{initializer_path}' must define '#{initializer_name}' class"
      end

      Object.const_get(initializer_name)
    end


    private


    def self._get_component_migrations_paths
      # All migrations paths under /components folder
      get_components.filter_map do |component|
        path = component[:path] + "/migrations"
        Dir.exist?(path) ? path : nil
      end
    end


    def self._get_component_helpers_paths
      # All helpers paths under /components folder
      Dir.glob(components_base_dir.join("**/helpers")).reject { |path| path.include?("test/") }
    end


    def self._get_component_routing_paths
      # All routes.rb files under /components folder
      Dir.glob(components_base_dir.join("**/routes.rb"))
    end


    def self._define_component_module(name)
      # Define module root, it allows not to fail if an initializer has compact class definition
      # For root components we define empty module at root level, for nested components we have to build the tree, like:
      # for "Accounting" we define module "Accounting",
      # for "Accounting::Taxes" we define "Accounting" and then "Taxes" (only when not defined)
      root = Object
      name.split("::").each do |part|
        root.const_set(part, Module.new) if !root.const_defined?(part)

        root = root.const_get(part)
      end
    end

    def self.log(message)
      return unless @verbose

      message = "[CF init] " + message
      if Rails.logger
        Rails.logger.info(message)
      else
        puts message
      end
    end

  end


  class ComponentNotFoundError < StandardError; end

end
