# frozen_string_literal: true

require 'yaml'

module Messhy
  class Configuration
    attr_reader :environment,
                :network,
                :nodes,
                :dns,
                :user,
                :ssh_key,
                :mtu,
                :listen_port,
                :keepalive,
                :verify_host_key

    def initialize(config_hash, environment = 'development')
      @environment = environment
      env_config = config_hash[environment] || {}

      @network = env_config['network'] || '10.8.0.0/24'
      @nodes = env_config['nodes'] || {}
      @dns = env_config['dns'] || {}
      @user = env_config['user'] || 'ubuntu'
      @ssh_key = File.expand_path(env_config['ssh_key'] || '~/.ssh/id_rsa')
      @mtu = env_config['mtu'] || 1280
      @listen_port = env_config['listen_port'] || 51_820
      @keepalive = env_config['keepalive'] || 25
      @verify_host_key = env_config.key?('verify_host_key') ? env_config['verify_host_key'] : true
    end

    def self.load(config_path = 'config/mesh.yml', environment = nil)
      environment ||= ENV['MESSHY_ENVIRONMENT'] || ENV['RAILS_ENV'] || 'development'

      raise Error, "Config file not found: #{config_path}" unless File.exist?(config_path)

      config_hash = YAML.load_file(config_path, aliases: true)
      new(config_hash, environment)
    end

    def node_names
      @nodes.keys
    end

    def node_config(name)
      @nodes[name]
    end

    def each_node(&)
      @nodes.each(&)
    end

    def network_prefix_length
      return 24 unless @network

      parts = @network.split('/')
      return 24 if parts.length < 2

      Integer(parts.last)
    rescue ArgumentError
      24
    end

    def validate!
      raise Error, 'No nodes defined' if @nodes.empty?

      @nodes.each do |name, config|
        raise Error, "Node #{name} missing 'host'" unless config['host']
        raise Error, "Node #{name} missing 'private_ip'" unless config['private_ip']
      end

      if dns_enabled?
        raise Error, 'DNS domain is required when dns is enabled' if dns_domains.empty?
        raise Error, 'DNS servers are required when dns is enabled' if dns_server_nodes.empty?
        raise Error, "Unsupported DNS provider: #{dns_provider}" unless %w[dnsmasq].include?(dns_provider)

        dns_server_nodes.each do |name|
          raise Error, "DNS server node not found: #{name}" unless node_config(name)
        end
      end

      true
    end

    def verify_host_key_mode
      case @verify_host_key
      when true, 'always', :always
        :always
      when 'accept_new', :accept_new
        :accept_new
      when 'never', :never, false
        :never
      else
        :always
      end
    end

    def dns_enabled?
      return false if @dns.nil? || @dns.empty?

      @dns.key?('enabled') ? @dns['enabled'] == true : true
    end

    def dns_provider
      value = @dns['provider'] || 'dnsmasq'
      value.to_s.strip
    end

    def dns_domain
      domains = dns_domains
      return domains.first unless domains.empty?

      value = @dns['domain'] || 'mesh'
      value.to_s.strip
    end

    def dns_domains
      domains = Array(@dns['domains']).map(&:to_s).map(&:strip).reject(&:empty?)
      return domains unless domains.empty?

      value = @dns['domain']
      return [] if value.nil?

      value = value.to_s.strip
      value.empty? ? [] : [value]
    end

    def dns_interface
      value = @dns['interface'] || 'wg0'
      value.to_s.strip
    end

    def dns_ttl
      value = @dns['ttl'] || 30
      value.to_i
    end

    def dns_server_nodes
      Array(@dns['servers']).map(&:to_s).reject(&:empty?)
    end

    def dns_records
      @dns['records'] || {}
    end

    def dns_auto_records?
      return true unless @dns.key?('auto_records')

      @dns['auto_records'] == true
    end
  end
end
