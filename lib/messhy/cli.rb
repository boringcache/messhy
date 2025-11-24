# frozen_string_literal: true

require 'thor'

module Messhy
  class CLI < Thor
    class_option :environment, aliases: '-e', default: ENV['MESSHY_ENVIRONMENT'] || ENV['RAILS_ENV'] || 'development'
    class_option :config, aliases: '-c', default: 'config/mesh.yml'

    desc 'setup', 'Setup WireGuard mesh network on all nodes'
    option :dry_run, type: :boolean, default: false
    option :skip_node, type: :string
    option :only_node, type: :string
    def setup
      config = load_config
      installer = Installer.new(config, dry_run: options[:dry_run])

      if options[:only_node]
        installer.setup_node(options[:only_node])
      elsif options[:skip_node]
        installer.setup(skip: options[:skip_node])
      else
        installer.setup
      end
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'keygen', 'Generate WireGuard keys without deploying configs'
    option :skip_node, type: :string
    def keygen
      config = load_config
      installer = Installer.new(config)
      installer.generate_keys(skip: options[:skip_node])
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'status', 'Show mesh network status'
    def status
      config = load_config
      health_checker = HealthChecker.new(config)
      health_checker.show_status
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'health', 'Alias for status'
    def health
      status
    end

    desc 'ping NODE', 'Ping a specific node'
    def ping(node)
      config = load_config
      health_checker = HealthChecker.new(config)
      health_checker.ping_node(node)
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'test-connectivity', 'Test connectivity between all nodes'
    def test_connectivity
      config = load_config
      health_checker = HealthChecker.new(config)
      health_checker.test_all
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'stats', 'Show traffic statistics'
    option :node, type: :string
    def stats
      config = load_config
      health_checker = HealthChecker.new(config)
      health_checker.show_stats(node: options[:node])
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'trust-hosts', 'Add each node host key to known_hosts using ssh-keyscan'
    option :known_hosts, type: :string, desc: 'Override path to known_hosts'
    option :force, type: :boolean, default: false, desc: 'Remove existing entries before scanning'
    option :hash_hosts, type: :boolean, default: false, desc: 'Hash hostnames in known_hosts'
    option :timeout, type: :numeric, default: HostTrustManager::DEFAULT_TIMEOUT, desc: 'ssh-keyscan timeout (seconds)'
    def trust_hosts
      config = load_config
      timeout = (options[:timeout] || HostTrustManager::DEFAULT_TIMEOUT).to_i
      manager = HostTrustManager.new(
        config,
        known_hosts_path: options[:known_hosts] || File.expand_path('~/.ssh/known_hosts'),
        timeout: timeout,
        hash_hosts: options[:hash_hosts],
        replace_existing: options[:force]
      )

      success = manager.trust_all_hosts
      exit 1 unless success
    end

    desc 'list', 'List all nodes'
    def list
      config = load_config
      config.each_node do |name, node_config|
        puts "#{name}: #{node_config['host']} (#{node_config['private_ip']})"
      end
    end

    desc 'show NAME', 'Show node details'
    def show(name)
      config = load_config
      node_config = config.node_config(name)

      unless node_config
        puts "Node not found: #{name}"
        exit 1
      end

      puts "Node: #{name}"
      puts "Host: #{node_config['host']}"
      puts "Private IP: #{node_config['private_ip']}"
      puts "Region: #{node_config['region']}" if node_config['region']

      health_checker = HealthChecker.new(config)
      health_checker.show_node_status(name)
    rescue SSHKit::Runner::ExecuteError => e
      handle_ssh_error(e, config)
    end

    desc 'version', 'Show version'
    def version
      puts "messhy #{Messhy::VERSION}"
    end

    private

    def load_config
      Configuration.load(options[:config], options[:environment])
    rescue StandardError => e
      puts "Error loading config: #{e.message}"
      exit 1
    end

    def handle_ssh_error(error, config)
      error_msg = error.message

      # Check if it's a host key mismatch error
      if error_msg.include?('fingerprint') && error_msg.include?('does not match')
        handle_host_key_mismatch_error(error_msg, config)
      elsif error_msg.include?('Authentication failed') || error_msg.include?('Permission denied')
        handle_authentication_error(error_msg, config)
      elsif error_msg.include?('Connection refused') || error_msg.include?('Connection timed out')
        handle_connection_error(error_msg, config)
      else
        handle_generic_ssh_error(error_msg, config)
      end

      exit 1
    end

    def handle_host_key_mismatch_error(error_msg, config)
      # Extract the host IP from the error message
      host_match = error_msg.match(/for "([^"]+)"/)
      host_ip = host_match[1] if host_match

      puts "\n❌ SSH Host Key Verification Failed"
      puts '=' * 60
      puts
      puts 'The SSH fingerprint for one or more hosts has changed.'
      puts 'This typically happens when a server is rebuilt or reinstalled.'
      puts

      if host_ip
        puts "Problematic host: #{host_ip}"
        puts
      end

      puts '🔧 How to fix this:'
      puts
      puts '  1. Update all host keys automatically (recommended):'
      puts "     #{environment_prefix(config)}messhy trust-hosts --force"
      puts
      puts '  2. Or manually remove just the problematic host:'
      if host_ip
        puts "     ssh-keygen -R #{host_ip}"
      else
        puts '     ssh-keygen -R <host_ip>'
      end
      puts
      puts '  3. Then retry the setup:'
      puts "     #{environment_prefix(config)}messhy setup"
      puts
      puts '=' * 60
    end

    def handle_authentication_error(_error_msg, config)
      puts "\n❌ SSH Authentication Failed"
      puts '=' * 60
      puts
      puts 'Could not authenticate to one or more hosts.'
      puts
      puts '🔧 Troubleshooting steps:'
      puts
      puts '  1. Verify the SSH key path is correct in your config:'
      puts "     Config file: #{options[:config]}"
      puts "     Environment: #{config.environment}"
      puts "     SSH key: #{config.ssh_key}"
      puts
      puts '  2. Check that the SSH key exists:'
      puts "     ls -la #{config.ssh_key}"
      puts
      puts '  3. Verify the SSH key is authorized on the remote hosts:'
      puts "     ssh -i #{config.ssh_key} #{config.user}@<host> 'cat ~/.ssh/authorized_keys'"
      puts
      puts '  4. Check file permissions (should be 600 for private key):'
      puts "     chmod 600 #{config.ssh_key}"
      puts
      puts '  5. Test manual SSH connection:'
      puts "     ssh -i #{config.ssh_key} #{config.user}@<host>"
      puts
      puts '=' * 60
    end

    def handle_connection_error(error_msg, _config)
      puts "\n❌ SSH Connection Failed"
      puts '=' * 60
      puts
      puts 'Could not connect to one or more hosts.'
      puts
      puts "Error: #{error_msg.lines.first&.strip}"
      puts
      puts '🔧 Troubleshooting steps:'
      puts
      puts '  1. Verify the hosts are online and reachable:'
      puts '     ping <host>'
      puts
      puts '  2. Check that SSH port is open (default: 22):'
      puts '     nc -zv <host> 22'
      puts
      puts '  3. Verify firewall rules allow SSH connections'
      puts
      puts '  4. Check that SSH service is running on remote hosts:'
      puts '     systemctl status sshd'
      puts
      puts '  5. Review host configuration in:'
      puts "     #{options[:config]}"
      puts
      puts '=' * 60
    end

    def handle_generic_ssh_error(error_msg, config)
      puts "\n❌ SSH Error"
      puts '=' * 60
      puts
      puts "Error: #{error_msg}"
      puts
      puts '🔧 Troubleshooting steps:'
      puts
      puts '  1. Trust SSH host keys for all nodes:'
      puts "     #{environment_prefix(config)}messhy trust-hosts"
      puts
      puts '  2. Verify configuration:'
      puts "     Config file: #{options[:config]}"
      puts "     Environment: #{config.environment}"
      puts
      puts '  3. Test manual SSH connection:'
      puts "     ssh -i #{config.ssh_key} #{config.user}@<host>"
      puts
      puts '  4. Check the detailed error message above for specific issues'
      puts
      puts '=' * 60
    end

    def environment_prefix(config)
      return '' if config.environment == 'development'

      "RAILS_ENV=#{config.environment} "
    end
  end
end
