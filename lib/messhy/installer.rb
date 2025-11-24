# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'time'
require 'digest'
require 'base64'

module Messhy
  # rubocop:disable Metrics/ClassLength
  class Installer
    attr_reader :config, :dry_run, :ssh_executor

    def initialize(config, dry_run: false)
      @config = config
      @dry_run = dry_run
      @ssh_executor = SSHExecutor.new(config)
      @node_keys = load_existing_keys
      @psk_map = load_existing_psks
    end

    def setup(skip: nil)
      puts '==> Setting up WireGuard mesh network'
      puts "Environment: #{config.environment}"
      puts "Nodes: #{config.node_names.join(', ')}"
      puts

      # Validate config
      config.validate!

      # Purge existing WireGuard configs
      puts '==> Cleaning up existing WireGuard installations...'
      purge_all(skip: skip) unless dry_run

      # Install WireGuard on all nodes (ensures wg binary exists for keygen)
      puts "\n==> Installing WireGuard on nodes..."
      install_wireguard_on_all_nodes(skip: skip)

      # Generate keys for all nodes
      puts "\n==> Generating WireGuard keys..."
      generate_all_keys(skip: skip)

      # Build configs
      puts "\n==> Building mesh configurations..."
      mesh_builder = MeshBuilder.new(config, @node_keys, @psk_map || {})
      configs = mesh_builder.build_all_configs

      # Upload configs and start WireGuard
      puts "\n==> Deploying configurations..."
      deploy_configs(configs, skip: skip)

      # Force restart all nodes
      puts "\n==> Restarting WireGuard on all nodes..."
      restart_all(skip: skip) unless dry_run

      # Verify connectivity
      puts "\n==> Verifying mesh connectivity..."
      verify_mesh(skip: skip)

      puts "\n✓ WireGuard mesh setup complete!"
    end

    def setup_node(node_name)
      puts "==> Setting up node: #{node_name}"

      raise Error, "Node not found: #{node_name}" unless config.node_config(node_name)

      config.validate!

      # Install WireGuard first so key generation works
      puts "\n==> Installing WireGuard tools..."
      ssh_executor.install_wireguard(node_name) unless dry_run

      # Load or generate keys for all nodes (needed for mesh config)
      puts "\n==> Ensuring key material exists..."
      generate_all_keys

      # Build and deploy config
      mesh_builder = MeshBuilder.new(config, @node_keys, @psk_map || {})
      config_content = mesh_builder.build_config_for_node(node_name)

      if dry_run
        puts "[DRY RUN] Would upload WireGuard config to #{node_name}"
      else
        ssh_executor.upload_config(node_name, config_content)
        ssh_executor.enable_and_start_wireguard(node_name)
      end

      puts "✓ Node #{node_name} setup complete"
    end

    def generate_keys(skip: nil)
      puts '==> Generating WireGuard keys (no deploy)'
      config.validate!
      puts "\n==> Installing WireGuard on nodes..."
      install_wireguard_on_all_nodes(skip: skip)
      puts "\n==> Generating WireGuard keys..."
      generate_all_keys(skip: skip)
      puts "✓ Keys stored in #{secrets_dir}" unless dry_run
    end

    def restart_node(node_name)
      puts "==> Restarting WireGuard on: #{node_name}"
      ssh_executor.restart_wireguard(node_name)
      puts '✓ Restarted'
    end

    def restart_all(skip: nil)
      puts '==> Restarting WireGuard on all nodes...'
      config.each_node do |node_name, _|
        next if skip && node_name == skip

        ssh_executor.restart_wireguard(node_name)
      end
      puts '✓ All nodes restarted'
    end

    def purge_all(skip: nil)
      config.each_node do |node_name, _|
        next if skip && node_name == skip

        ssh_executor.purge_wireguard(node_name)
      end
    end

    private

    def generate_all_keys(skip: nil)
      config.each_node do |node_name, _|
        next if skip && node_name == skip

        if @node_keys[node_name]
          puts "  ✓ Using stored keys for #{node_name}"
          next
        end

        puts "  Generating keys for #{node_name}..."
        if dry_run
          @node_keys[node_name] = fake_keypair_for(node_name)
        else
          new_keypair = ssh_executor.generate_keypair_on_node(node_name)
          @node_keys[node_name] = new_keypair
          store_keypair(node_name, new_keypair)
        end
      end

      generate_psk_map(skip: skip)
    end

    def generate_psk_map(skip: nil)
      node_names = config.node_names
      changed = false

      node_names.each_with_index do |node1, i|
        next if skip && node1 == skip

        peers = node_names[(i + 1)..] || []
        peers.each do |node2|
          next if skip && node2 == skip

          pair_key = [node1, node2].sort.join('-')
          next if @psk_map[pair_key]

          if dry_run
            @psk_map[pair_key] = fake_psk_for(pair_key)
          else
            @psk_map[pair_key] = ssh_executor.generate_psk_on_node(node1)
            changed = true
          end
        end
      end

      persist_psk_map if changed
    end

    def install_wireguard_on_all_nodes(skip: nil)
      if skip
        config.each_node do |node_name, _|
          next if node_name == skip

          puts "  Installing on #{node_name}..."
          ssh_executor.install_wireguard(node_name) unless dry_run
        end
      else
        puts '  Installing WireGuard on all nodes in parallel...'
        ssh_executor.install_wireguard_on_all_nodes unless dry_run
      end
    end

    def deploy_configs(configs, skip: nil)
      if skip
        configs.each do |node_name, config_content|
          next if node_name == skip

          puts "  Deploying to #{node_name}..."

          if dry_run
            puts '    [DRY RUN] Would upload config and restart WireGuard'
          else
            ssh_executor.upload_config(node_name, config_content)
            ssh_executor.enable_and_start_wireguard(node_name)
          end
        end
      else
        puts '  Deploying configurations to all nodes in parallel...'
        if dry_run
          configs.each_key do |node_name|
            puts "    [DRY RUN] Would deploy to #{node_name}"
          end
        else
          ssh_executor.upload_and_start_configs(configs)
        end
      end
    end

    def verify_mesh(skip: nil)
      return if dry_run

      HealthChecker.new(config)

      # Give WireGuard a moment to establish connections
      sleep 3

      all_ok = true
      config.each_node do |node_name, _|
        next if skip && node_name == skip

        begin
          status = ssh_executor.get_wireguard_status(node_name)

          # Count handshakes
          handshakes = status.scan(/latest handshake: (.+?)$/)
          peer_count = status.scan('peer:').size

          if peer_count.positive?
            handshake_count = handshakes.size
            if handshake_count.positive?
              puts "  ✓ #{node_name} - #{peer_count} peers, #{handshake_count} handshakes"
            else
              puts "  ⚠ #{node_name} - #{peer_count} peers, no handshakes yet"
            end
          else
            puts "  ✗ #{node_name} - No peers connected"
            all_ok = false
          end
        rescue StandardError => e
          puts "  ✗ #{node_name} - Error: #{e.message}"
          all_ok = false
        end
      end

      return if all_ok

      puts "\nNote: Handshakes may take a few seconds to establish."
      puts "Run 'messhy status' to check detailed connectivity."
    end

    def secrets_dir
      @secrets_dir ||= File.expand_path(File.join('.secrets', 'wireguard'), Dir.pwd)
    end

    def psk_file_path
      File.join(secrets_dir, 'psks.yml')
    end

    def load_existing_keys
      return {} unless Dir.exist?(secrets_dir)

      Dir.glob(File.join(secrets_dir, '*.yml')).each_with_object({}) do |path, acc|
        next if File.basename(path) == 'psks.yml'

        data = YAML.load_file(path, aliases: true)
        node_name = (data['node'] || File.basename(path, '.yml')).to_s
        next unless config.node_config(node_name)
        next unless data['private_key'] && data['public_key']

        acc[node_name] = {
          private_key: data['private_key'],
          public_key: data['public_key']
        }
      rescue StandardError
        next
      end
    end

    def load_existing_psks
      return {} unless File.exist?(psk_file_path)

      data = YAML.load_file(psk_file_path, aliases: true)
      pairs = data['pairs'] || {}
      pairs.transform_keys(&:to_s)
    rescue StandardError
      {}
    end

    def store_keypair(node_name, keypair)
      FileUtils.mkdir_p(secrets_dir)
      path = File.join(secrets_dir, "#{node_name}.yml")
      payload = {
        'node' => node_name,
        'private_key' => keypair[:private_key],
        'public_key' => keypair[:public_key],
        'generated_at' => Time.now.utc.iso8601
      }
      File.write(path, payload.to_yaml)
      File.chmod(0o600, path)
    end

    def persist_psk_map
      FileUtils.mkdir_p(secrets_dir)
      payload = {
        'generated_at' => Time.now.utc.iso8601,
        'pairs' => @psk_map
      }
      File.write(psk_file_path, payload.to_yaml)
      File.chmod(0o600, psk_file_path)
    end

    def fake_keypair_for(node_name)
      digest = Digest::SHA256.hexdigest(node_name)
      base = Base64.strict_encode64([digest].pack('H*'))
      {
        private_key: base[0, 44],
        public_key: base.reverse[0, 44]
      }
    end

    def fake_psk_for(pair_key)
      base = Base64.strict_encode64(Digest::SHA256.digest(pair_key))
      base[0, 44]
    end
  end
  # rubocop:enable Metrics/ClassLength
end
