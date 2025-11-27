if defined?(Rails::Railtie)
  require 'rails/railtie'

  module Messhy
    class Railtie < Rails::Railtie
      railtie_name :messhy

      rake_tasks do
        path = File.expand_path('../tasks/messhy.rake', __dir__)
        load path if File.exist?(path)
      end

      generators do
        require_relative 'generators/messhy/install_generator'
      end
    end
  end
end
