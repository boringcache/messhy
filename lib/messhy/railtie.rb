if defined?(Rails::Railtie)
  require 'rails/railtie'

  module Messhy
    class Railtie < Rails::Railtie
      railtie_name :messhy

      rake_tasks do
        load 'tasks/messhy.rake'
      end

      generators do
        require_relative 'generators/messhy/install_generator'
      end
    end
  end
end
