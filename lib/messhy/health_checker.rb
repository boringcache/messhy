# frozen_string_literal: true

require 'timeout'
require_relative 'wireguard_status_parser'

module Messhy
  class HealthChecker
    include WireguardStatusParser

    HANDSHAKE_STALENESS_LIMIT = 180 # seconds

    attr_reader :config

    def initialize(config)
      @config = config
      @ssh_executor = SSHExecutor.new(config)
    end

    def show_status
      puts '==> WireGuard Mesh Status'
      puts "Environment: #{config.environment}"
      puts

      config.each_node do |node_name, _node_config|
        show_node_status(node_name)
        puts
      end
    end

    def show_node_status(node_name)
      node_config = config.node_config(node_name)

      begin
        status = @ssh_executor.get_wireguard_status(node_name)

        # Parse status output
        peers = status.scan(/peer: (.+?)$/).flatten

        if peers.any?
          puts "✓ #{node_name} (#{node_config['private_ip']}) - connected to #{peers.size} peers"

          # Show basic peer info
          status.split('peer:').drop(1).each do |peer_block|
            endpoint = extract_endpoint(peer_block)
            next unless endpoint

            stats = extract_transfer_stats(peer_block)
            puts "  └─ Peer: #{endpoint} - #{stats[:received]} rx, #{stats[:sent]} tx"
          end
        else
          puts "✗ #{node_name} (#{node_config['private_ip']}) - 0 peers (DOWN)"
        end
      rescue StandardError => e
        puts "✗ #{node_name} (#{node_config['private_ip']}) - Error: #{e.message}"
      end
    end

    def ping_node(node_or_ip)
      # Determine if input is node name or IP
      target_node = nil
      target_ip = nil

      if node_or_ip =~ /^\d+\.\d+\.\d+\.\d+$/
        # It's an IP
        target_ip = node_or_ip
        target_node = config.nodes.find { |_, cfg| cfg['private_ip'] == target_ip }&.first
      else
        # It's a node name
        target_node = node_or_ip
        node_config = config.node_config(target_node)
        target_ip = node_config['private_ip'] if node_config
      end

      unless target_ip
        puts "Node or IP not found: #{node_or_ip}"
        return
      end

      puts "Pinging #{target_node || target_ip} (#{target_ip})..."

      # Try pinging from each other node
      config.each_node do |source_node, _|
        next if source_node == target_node # Skip pinging self

        success = @ssh_executor.ping_node_from(source_node, target_ip)
        status = success ? '✓' : '✗'
        puts "  #{status} from #{source_node}"
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def test_all
      puts '==> Testing mesh connectivity...'
      puts
      puts 'Note: This test may take a while. WireGuard status shows all peers connected.'
      puts

      all_ok = true
      tested_pairs = Set.new
      test_count = 0
      total_tests = config.node_names.size * (config.node_names.size - 1) / 2

      status_cache = {}
      config.each_node do |source_name, _source_config|
        config.each_node do |target_name, target_config|
          next if source_name == target_name

          pair_key = [source_name, target_name].sort.join('-')
          next if tested_pairs.include?(pair_key)

          tested_pairs.add(pair_key)
          test_count += 1
          target_ip = target_config['private_ip']

          print "[#{test_count}/#{total_tests}] Testing #{source_name} → #{target_name} (#{target_ip})... "
          $stdout.flush

          success = false
          begin
            Timeout.timeout(3) do
              success = @ssh_executor.ping_node_from(source_name, target_ip) ||
                        @ssh_executor.test_tcp_connectivity(source_name, target_ip, 22)
            end
          rescue StandardError
            success = false
          end

          if success
            puts '✓'
          elsif handshake_recent?(source_name, target_config['private_ip'], status_cache)
            puts '✓ (handshake)'
          else
            puts '✗ (ICMP/TCP may be blocked, and no recent WireGuard handshake)'
            all_ok = false
          end
          $stdout.flush
        end
      end

      puts
      puts 'Note: When ICMP/TCP probes fail, we fall back to recent WireGuard handshakes.'
      puts 'If a pair still reports a failure, there has been no recent handshake—check UDP 51820 and ' \
           'keepalive/route settings.'
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def show_stats(node: nil)
      if node
        show_node_stats(node)
      else
        config.each_node do |node_name, _|
          show_node_stats(node_name)
          puts
        end
      end
    end

    private

    def handshake_recent?(source_name, target_ip, status_cache)
      status = status_cache[source_name] ||= @ssh_executor.get_wireguard_status(source_name)
      peer_block = WireguardStatusParser.extract_peer_block(status, target_ip)
      return false unless peer_block

      seconds = WireguardStatusParser.extract_handshake_time(peer_block)
      return false unless seconds

      seconds <= HANDSHAKE_STALENESS_LIMIT
    rescue StandardError
      false
    end

    def show_node_stats(node_name)
      node_config = config.node_config(node_name)

      puts "==> Stats for #{node_name} (#{node_config['private_ip']})"

      begin
        status = @ssh_executor.get_wireguard_status(node_name)

        # Parse and display stats
        status.split('peer:').drop(1).each_with_index do |peer_block, index|
          puts "\nPeer ##{index + 1}:"

          endpoint = extract_endpoint(peer_block)
          puts "  Endpoint: #{endpoint}" if endpoint

          allowed_ips = extract_allowed_ips(peer_block)
          puts "  Allowed IPs: #{allowed_ips}" if allowed_ips

          handshake = peer_block[/latest handshake: (.+?)$/, 1]
          puts "  Last handshake: #{handshake}" if handshake

          stats = extract_transfer_stats(peer_block)
          puts "  Received: #{stats[:received]}"
          puts "  Sent: #{stats[:sent]}"
        end
      rescue StandardError => e
        puts "Error: #{e.message}"
      end
    end
  end
end
