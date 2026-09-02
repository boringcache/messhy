# frozen_string_literal: true

require 'erb'

module Messhy
  class MeshBuilder
    attr_reader :config, :node_keys, :psk_map

    def initialize(config, node_keys = {}, psk_map = {})
      @config = config
      @node_keys = node_keys
      @psk_map = psk_map
    end

    # rubocop:disable Metrics/AbcSize
    def build_config_for_node(node_name)
      node_config = config.node_config(node_name)
      raise Error, "Node not found: #{node_name}" unless node_config

      # Get keys for this node
      keys = node_keys[node_name]
      raise Error, "Keys not found for node: #{node_name}" unless keys

      template_path = File.join(Messhy.root, 'templates', 'wg0.conf.erb')
      template = ERB.new(File.read(template_path), trim_mode: '-')

      # Prepare data for template
      interface_ip = node_config['mesh_ip']
      prefix_length = config.network_prefix_length
      private_key = keys[:private_key]
      listen_port = node_config['listen_port'] || config.listen_port
      mtu = config.mtu

      # DNS config for PostUp persistence
      dns_server_ips = []
      dns_domain = nil
      dns_interface = nil
      if config.dns_enabled?
        dns_domain = config.dns_domain
        dns_interface = config.dns_interface
        dns_server_ips = config.dns_server_nodes.filter_map do |name|
          config.node_config(name)&.dig('mesh_ip')
        end
      end

      is_dns_server = config.dns_enabled? && config.dns_server_nodes.include?(node_name)

      # Build peers list (all other nodes)
      peers = []
      config.each_node do |peer_name, peer_config|
        next if peer_name == node_name # Skip self

        peer_keys = node_keys[peer_name]
        next unless peer_keys # Skip if keys not available

        # Get symmetric PSK for this peer pair
        pair_key = [node_name, peer_name].sort.join('-')
        psk = psk_map[pair_key]
        endpoint = config.peer_endpoint_for(node_name, peer_name)
        peer_listen_port = peer_config['listen_port'] || config.listen_port

        peers << {
          name: peer_name,
          public_key: peer_keys[:public_key],
          preshared_key: psk,
          allowed_ips: "#{peer_config['mesh_ip']}/32",
          endpoint: "#{endpoint}:#{peer_listen_port}",
          keepalive: config.keepalive
        }
      end

      # Render template
      binding_context = binding
      template.result(binding_context)
    end
    # rubocop:enable Metrics/AbcSize

    def build_all_configs
      configs = {}
      config.each_node do |node_name, _|
        configs[node_name] = build_config_for_node(node_name)
      end
      configs
    end
  end
end
