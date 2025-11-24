# frozen_string_literal: true

require_relative 'messhy/version'
require_relative 'messhy/configuration'
require_relative 'messhy/wireguard_status_parser'
require_relative 'messhy/installer'
require_relative 'messhy/mesh_builder'
require_relative 'messhy/ssh_executor'
require_relative 'messhy/health_checker'
require_relative 'messhy/host_trust_manager'
require_relative 'messhy/cli'

module Messhy
  class Error < StandardError; end

  def self.root
    File.expand_path('..', __dir__)
  end
end

require_relative 'messhy/railtie'
