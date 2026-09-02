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
                :ssh_known_hosts_file,
                :mtu,
                :listen_port,
                :keepalive,
                :verify_host_key

    def initialize(config_hash, environment = 'development')
      @environment = environment
      env_config = config_hash[environment] || {}

      @network = env_config['network'] || '10.8.0.0/24'
      @nodes = normalize_nodes(env_config['nodes'] || {})
      @dns = env_config['dns'] || {}
      @user = env_config['user'] || 'ubuntu'
      @ssh_key = File.expand_path(env_config['ssh_key'] || '~/.ssh/id_rsa')
      @ssh_known_hosts_file = optional_path(env_config['ssh_known_hosts_file'])
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

    def peer_endpoint_for(node_name, peer_name)
      node = node_config(node_name)
      peer = node_config(peer_name)

      return peer['host'] unless node['lan'] && peer['lan']
      return peer['host'] unless node.dig('lan', 'network') == peer.dig('lan', 'network')

      peer.dig('lan', 'ip')
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

      @nodes.each { |name, config| validate_node!(name, config) }

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

    def jump_host_config(name)
      jump_host = node_config(name)&.dig('jump_host')
      return unless jump_host

      node_config(jump_host) || raise(Error, "Node #{name} jump_host not found: #{jump_host}")
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

    private

    def optional_path(path)
      File.expand_path(path) if path
    end

    def normalize_nodes(nodes)
      nodes.to_h do |name, config|
        [name, normalize_node(name, config)]
      end
    end

    def normalize_node(name, config)
      config = config.dup
      legacy_mesh_ip = config.delete('private_ip')

      if config['mesh_ip'] && legacy_mesh_ip && config['mesh_ip'] != legacy_mesh_ip
        raise Error, "Node #{name} has conflicting 'mesh_ip' and deprecated 'private_ip' values"
      end

      config['mesh_ip'] ||= legacy_mesh_ip
      config
    end

    def validate_node!(name, config)
      raise Error, "Node #{name} missing 'host'" unless config['host']
      raise Error, "Node #{name} missing 'mesh_ip'" unless config['mesh_ip']

      validate_lan!(name, config['lan']) if config['lan']

      jump_host = config['jump_host']
      return unless jump_host

      raise Error, "Node #{name} cannot use itself as jump_host" if jump_host == name
      raise Error, "Node #{name} jump_host not found: #{jump_host}" unless node_config(jump_host)
    end

    def validate_lan!(name, lan)
      raise Error, "Node #{name} 'lan' must be a mapping" unless lan.is_a?(Hash)
      raise Error, "Node #{name} lan missing 'network'" if lan['network'].to_s.empty?
      raise Error, "Node #{name} lan missing 'ip'" if lan['ip'].to_s.empty?
    end
  end
end
