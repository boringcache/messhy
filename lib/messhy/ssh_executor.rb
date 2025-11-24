# frozen_string_literal: true

require 'sshkit'
require 'sshkit/dsl'
require 'stringio'

module Messhy
  class SSHExecutor
    include SSHKit::DSL

    attr_reader :config

    def initialize(config)
      @config = config
      setup_sshkit
    end

    def execute_on_node(node_name, &)
      node_config = config.node_config(node_name)
      raise Error, "Node not found: #{node_name}" unless node_config

      host = host_for(node_name, node_config)
      on(host, &)
    end

    def execute_on_all_nodes(skip: nil, &)
      hosts = config.each_node.with_object([]) do |(node_name, node_config), collection|
        next if skip && node_name == skip

        collection << host_for(node_name, node_config)
      end

      return if hosts.empty?

      on(hosts, in: :parallel, &)
    end

    def install_wireguard(node_name)
      execute_on_node(node_name) do
        # Check if WireGuard is already installed
        if test('[ -f /usr/bin/wg ]')
          info 'WireGuard already installed'
        else
          info 'Installing WireGuard...'
          execute :sudo, 'apt-get', 'update', '-qq'
          execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'wireguard',
                  'iputils-ping'
        end

        # Install ping if not available
        unless test('which', 'ping', raise_on_error: false)
          info 'Installing ping utility...'
          execute :sudo, 'apt-get', 'update', '-qq', raise_on_error: false
          execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'iputils-ping',
                  raise_on_error: false
        end
      end
    end

    def generate_keypair_on_node(node_name)
      keypair = {}
      execute_on_node(node_name) do
        keypair[:private_key] = capture('wg', 'genkey').strip
        keypair[:public_key] = capture(:echo, keypair[:private_key], '|', 'wg', 'pubkey').strip
      end
      keypair
    end

    def generate_psk_on_node(node_name)
      psk = nil
      execute_on_node(node_name) do
        psk = capture('wg', 'genpsk').strip
      end
      psk
    end

    def install_wireguard_on_all_nodes(skip: nil)
      execute_on_all_nodes(skip: skip) do
        # Check if WireGuard is already installed
        if test('[ -f /usr/bin/wg ]')
          info 'WireGuard already installed'
        else
          info 'Installing WireGuard...'
          execute :sudo, 'apt-get', 'update', '-qq'
          execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'wireguard',
                  'iputils-ping'
        end

        # Install ping if not available
        unless test('which', 'ping', raise_on_error: false)
          info 'Installing ping utility...'
          execute :sudo, 'apt-get', 'update', '-qq', raise_on_error: false
          execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'iputils-ping',
                  raise_on_error: false
        end
      end
    end

    def upload_config(node_name, config_content)
      execute_on_node(node_name) do
        # Create temporary file
        temp_file = '/tmp/wg0.conf'
        upload! StringIO.new(config_content), temp_file

        # Move to /etc/wireguard with proper permissions
        execute :sudo, 'mv', temp_file, '/etc/wireguard/wg0.conf'
        execute :sudo, 'chmod', '600', '/etc/wireguard/wg0.conf'
      end
    end

    def upload_and_start_configs(configs)
      hosts = configs.filter_map do |node_name, config_content|
        node_config = config.node_config(node_name)
        next unless node_config

        host = host_for(node_name, node_config)
        manage_property(host.properties, :config_content, config_content)
        host
      end

      return if hosts.empty?

      executor = self

      on hosts, in: :parallel do |host|
        properties = host.properties
        config_content = executor.send(:manage_property, properties, :config_content)
        temp_file = '/tmp/wg0.conf'
        upload! StringIO.new(config_content), temp_file
        execute :sudo, 'mv', temp_file, '/etc/wireguard/wg0.conf'
        execute :sudo, 'chmod', '600', '/etc/wireguard/wg0.conf'
        execute :sudo, 'systemctl', 'enable', 'wg-quick@wg0'
        if test('systemctl is-active wg-quick@wg0')
          execute :sudo, 'systemctl', 'restart', 'wg-quick@wg0'
        else
          execute :sudo, 'systemctl', 'start', 'wg-quick@wg0'
        end
      end
    end

    def enable_and_start_wireguard(node_name)
      execute_on_node(node_name) do
        # Enable systemd service
        execute :sudo, 'systemctl', 'enable', 'wg-quick@wg0'

        # Restart WireGuard
        if test('systemctl is-active wg-quick@wg0')
          execute :sudo, 'systemctl', 'restart', 'wg-quick@wg0'
        else
          execute :sudo, 'systemctl', 'start', 'wg-quick@wg0'
        end
      end
    end

    def get_wireguard_status(node_name)
      result = nil
      execute_on_node(node_name) do
        result = capture(:sudo, 'wg', 'show', 'wg0')
      end
      result
    end

    def ping_node_from(source_node, target_ip)
      success = false
      execute_on_node(source_node) do
        if test('which', 'ping', raise_on_error: false)
          success = test('timeout', '3', 'ping', '-c', '1', '-W', '1', '-I', 'wg0', target_ip, raise_on_error: false)
        end
      end
      success
    rescue StandardError
      false
    end

    def test_tcp_connectivity(source_node, target_ip, port = 22)
      success = false
      execute_on_node(source_node) do
        success = test('timeout', '2', 'bash', '-c',
                       "exec 3<>/dev/tcp/#{target_ip}/#{port} 2>&1 && exec 3<&- && exec 3>&-", raise_on_error: false)
      end
      success
    rescue StandardError
      false
    end

    def restart_wireguard(node_name)
      execute_on_node(node_name) do
        # Stop service first
        if test('systemctl is-active wg-quick@wg0', raise_on_error: false)
          execute :sudo, 'systemctl', 'stop', 'wg-quick@wg0'
        end

        # Remove interface if it exists
        if test('[ -d /sys/class/net/wg0 ]', raise_on_error: false)
          execute :sudo, 'ip', 'link', 'delete', 'wg0', raise_on_error: false
        end

        # Start fresh
        execute :sudo, 'systemctl', 'start', 'wg-quick@wg0'
      end
    end

    def stop_wireguard(node_name)
      execute_on_node(node_name) do
        execute :sudo, 'systemctl', 'stop', 'wg-quick@wg0' if test('systemctl is-active wg-quick@wg0')
      end
    end

    def purge_wireguard(node_name)
      execute_on_node(node_name) do
        # Stop and disable service
        if test('systemctl is-active wg-quick@wg0', raise_on_error: false)
          execute :sudo, 'systemctl', 'stop', 'wg-quick@wg0', raise_on_error: false
        end
        if test('systemctl is-enabled wg-quick@wg0', raise_on_error: false)
          execute :sudo, 'systemctl', 'disable', 'wg-quick@wg0', raise_on_error: false
        end

        # Remove interface
        if test('[ -d /sys/class/net/wg0 ]', raise_on_error: false)
          execute :sudo, 'ip', 'link', 'delete', 'wg0', raise_on_error: false
        end

        # Remove config
        if test('[ -f /etc/wireguard/wg0.conf ]', raise_on_error: false)
          execute :sudo, 'rm', '-f', '/etc/wireguard/wg0.conf', raise_on_error: false
        end
      end
    end

    private

    def install_wireguard_packages
      # Check if WireGuard is already installed
      if test('[ -f /usr/bin/wg ]')
        info 'WireGuard already installed'
      else
        info 'Installing WireGuard...'
        execute :sudo, 'apt-get', 'update', '-qq'
        execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'wireguard',
                'iputils-ping'
      end

      # Install ping if not available
      return if test('which', 'ping', raise_on_error: false)

      info 'Installing ping utility...'
      execute :sudo, 'apt-get', 'update', '-qq', raise_on_error: false
      execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'iputils-ping',
              raise_on_error: false
    end

    def setup_sshkit
      SSHKit.config.output_verbosity = Logger::INFO
      SSHKit.config.use_format :pretty

      SSHKit::Backend::Netssh.configure do |ssh|
        ssh.ssh_options = build_ssh_options
      end
    end

    def build_ssh_options
      options = {
        forward_agent: false,
        auth_methods: ['publickey'],
        verify_host_key: config.verify_host_key_mode
      }

      if File.exist?(config.ssh_key)
        options[:keys] = [config.ssh_key]
        options[:keys_only] = true
      end

      options
    end

    def host_for(node_name, node_config)
      host = SSHKit::Host.new(node_config['host'])
      ssh_user = node_config['ssh_user'] || node_config['user'] || config.user
      host.user = ssh_user if ssh_user

      ssh_port = node_config['ssh_port'] || node_config['port']
      host.port = ssh_port if ssh_port

      if node_config['ssh_key']
        keys = Array(node_config['ssh_key']).map { |path| File.expand_path(path) }
        merged = (host.ssh_options || {}).merge(keys: keys, keys_only: true)
        host.ssh_options = merged
      end

      manage_property(host.properties, :node_name, node_name)
      host
    end

    def manage_property(properties, key, value = nil)
      if value.nil?
        # Fetch mode
        properties.respond_to?(:fetch) ? properties.fetch(key) : properties[key]
      else
        # Assign mode
        properties.respond_to?(:set) ? properties.set(key, value) : properties[key] = value
      end
    end
  end
end
