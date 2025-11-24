# frozen_string_literal: true

require 'open3'
require 'fileutils'

module Messhy
  class HostTrustManager
    DEFAULT_TIMEOUT = 5
    DEFAULT_KEY_TYPES = %w[ed25519 ecdsa rsa].freeze

    # rubocop:disable Metrics/ParameterLists
    def initialize(config,
                   known_hosts_path: File.expand_path('~/.ssh/known_hosts'),
                   timeout: DEFAULT_TIMEOUT,
                   key_types: DEFAULT_KEY_TYPES,
                   hash_hosts: false,
                   replace_existing: false)
      @config = config
      @known_hosts_path = File.expand_path(known_hosts_path)
      @timeout = timeout
      @key_types = Array(key_types).join(',')
      @hash_hosts = hash_hosts
      @replace_existing = replace_existing
    end
    # rubocop:enable Metrics/ParameterLists

    def trust_all_hosts
      ensure_ssh_keyscan!
      ensure_known_hosts_dir!

      existing_entries = load_known_host_lines
      trusted = []
      failed = []

      @config.each_node do |node_name, node_config|
        host = node_config['host']
        next unless host

        port = node_config['ssh_port'] || node_config['port']
        label = port ? "#{host}:#{port}" : host

        puts "==> Fetching host key for #{node_name} (#{label})"
        remove_host_entries(host, port) if @replace_existing
        output = scan_host(host, port)

        if output
          append_unique_entries(output, existing_entries)
          trusted << label
          puts "  ✓ Added #{label} to #{@known_hosts_path}"
        else
          warn "  ✗ Failed to scan #{label}"
          failed << label
        end
      end

      summary(trusted, failed)
      failed.empty?
    end

    private

    def ensure_ssh_keyscan!
      return if system('command -v ssh-keyscan >/dev/null 2>&1')

      raise Error, 'ssh-keyscan command not found. Install OpenSSH client utilities.'
    end

    def ensure_known_hosts_dir!
      FileUtils.mkdir_p(File.dirname(@known_hosts_path))
      FileUtils.touch(@known_hosts_path) unless File.exist?(@known_hosts_path)
    end

    def load_known_host_lines
      return Set.new unless File.exist?(@known_hosts_path)

      Set.new(File.readlines(@known_hosts_path).map(&:strip))
    end

    def scan_host(host, port = nil)
      cmd = ['ssh-keyscan', '-T', @timeout.to_s]
      cmd << '-H' if @hash_hosts
      cmd += ['-p', port.to_s] if port
      cmd += ['-t', @key_types, host]
      stdout, stderr, status = Open3.capture3(*cmd)
      return stdout unless status.exitstatus != 0 || stdout.strip.empty?

      if stderr.strip.empty?
        warn "    Connection timeout or host unreachable (timeout: #{@timeout}s)"
        warn '    Check firewall rules, network connectivity, and SSH service'
      else
        warn "    ssh-keyscan error: #{stderr.strip}"
      end
      nil
    end

    def remove_host_entries(host, port = nil)
      return unless system('command -v ssh-keygen >/dev/null 2>&1')

      label = port ? "[#{host}]:#{port}" : host
      stdout, stderr, status = Open3.capture3('ssh-keygen', '-R', label, '-f', @known_hosts_path)
      if status.success?
        trimmed = stdout.strip
        puts "    Removed existing known_hosts entry for #{label}" unless trimmed.empty?
      else
        warn "    ssh-keygen -R error for #{label}: #{stderr.strip}" unless stderr.strip.empty?
      end
    end

    def append_unique_entries(output, existing_entries)
      File.open(@known_hosts_path, 'a') do |file|
        output.each_line do |line|
          normalized = line.strip
          next if normalized.empty? || existing_entries.include?(normalized)

          file.puts line
          existing_entries.add(normalized)
        end
      end
    end

    def summary(trusted, failed)
      puts "\n==> Host trust summary"
      puts "  Trusted: #{trusted.count}"
      puts "  Failed: #{failed.count}"
      return if failed.empty?

      puts
      puts '  ❌ Hosts that could not be scanned:'
      failed.each { |host| puts "    - #{host}" }
      puts
      puts '  🔧 Troubleshooting steps:'
      puts '    1. Verify the hosts are online and reachable'
      puts '    2. Check firewall rules allow SSH connections (port 22 by default)'
      puts '    3. Ensure SSH service is running on the remote hosts'
      puts '    4. Try increasing the timeout with: --timeout 10'
      puts '    5. Test manual SSH connection: ssh -i <ssh_key> <user>@<host>'
    end
  end
end
