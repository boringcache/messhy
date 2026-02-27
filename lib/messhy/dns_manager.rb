# frozen_string_literal: true

require 'stringio'

module Messhy
  class DnsManager
    attr_reader :config, :ssh_executor, :dry_run

    def initialize(config, ssh_executor: SSHExecutor.new(config), dry_run: false, skip: nil)
      @config = config
      @ssh_executor = ssh_executor
      @dry_run = dry_run
      @skip = skip
    end

    def setup
      return unless config.dns_enabled?

      case config.dns_provider
      when 'dnsmasq'
        setup_dnsmasq
      else
        raise Error, "Unsupported DNS provider: #{config.dns_provider}"
      end
    end

    private

    def setup_dnsmasq
      domain = config.dns_domain
      interface = config.dns_interface
      ttl = config.dns_ttl
      server_nodes = config.dns_server_nodes
      server_ips = server_nodes.map { |name| config.node_config(name)['private_ip'] }

      records = build_records(domain)

      server_nodes.each do |node|
        next if @skip && node == @skip

        server_ip = config.node_config(node)['private_ip']
        conf = build_dnsmasq_conf(domain, interface, server_ip, records, ttl)

        if dry_run
          puts "[DRY RUN] Would install dnsmasq and write /etc/dnsmasq.d/messhy.conf on #{node}"
          next
        end

        ssh_executor.execute_on_node(node) do
          execute :sudo, 'apt-get', 'update', '-qq'
          execute :sudo, 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '-qq', 'dnsmasq'
          upload! StringIO.new(conf), '/tmp/messhy-dns.conf'
          execute :sudo, 'mv', '/tmp/messhy-dns.conf', '/etc/dnsmasq.d/messhy.conf'
          execute :sudo, 'chown', 'root:root', '/etc/dnsmasq.d/messhy.conf'
          execute :sudo, 'chmod', '644', '/etc/dnsmasq.d/messhy.conf'
          execute :sudo, 'systemctl', 'enable', 'dnsmasq'
          execute :sudo, 'systemctl', 'restart', 'dnsmasq'
        end
      end

      config.each_node do |node_name, _|
        next if @skip && node_name == @skip

        if dry_run
          puts "[DRY RUN] Would configure DNS on #{node_name} (#{interface}) for #{domain} -> #{server_ips.join(', ')}"
          next
        end

        configure_client_dns(node_name, interface, domain, server_ips)
      end
    end

    def configure_client_dns(node_name, interface, domain, server_ips)
      ssh_executor.execute_on_node(node_name) do
        if test('which', 'resolvectl', raise_on_error: false)
          execute :sudo, 'systemctl', 'enable', '--now', 'systemd-resolved', raise_on_error: false
          execute :sudo, 'resolvectl', 'dns', interface, *server_ips
          execute :sudo, 'resolvectl', 'domain', interface, "~#{domain}"
          execute :sudo, 'resolvectl', 'flush-caches', raise_on_error: false
        elsif test('[ -d /etc/resolvconf/resolv.conf.d ]', raise_on_error: false)
          head_path = '/etc/resolvconf/resolv.conf.d/head'
          content = server_ips.map { |ip| "nameserver #{ip}" }.join("\n") + "\n"
          upload! StringIO.new(content), '/tmp/messhy-resolv.conf'
          execute :sudo, 'mv', '/tmp/messhy-resolv.conf', head_path
          execute :sudo, 'chmod', '644', head_path
          execute :sudo, 'resolvconf', '-u'
        else
          info 'resolvectl not found; skipping DNS config'
        end
      end
    end

    def build_records(domain)
      records = {}

      if config.dns_auto_records?
        config.each_node do |name, node_config|
          hostname = "#{sanitize_dns_label(name)}.#{domain}"
          records[hostname] ||= []
          records[hostname] << node_config['private_ip']
        end
      end

      config.dns_records.each do |hostname, targets|
        fqdn = normalize_hostname(hostname, domain)
        Array(targets).each do |target|
          ip = resolve_target(target)
          next if ip.to_s.strip.empty?

          records[fqdn] ||= []
          records[fqdn] << ip
        end
      end

      records.transform_values { |ips| ips.uniq }
    end

    def resolve_target(target)
      return '' if target.nil?

      node = config.node_config(target.to_s)
      return node['private_ip'] if node

      target.to_s
    end

    def normalize_hostname(name, domain)
      value = name.to_s.strip
      return '' if value.empty?

      return value if value.include?('.')

      "#{sanitize_dns_label(value)}.#{domain}"
    end

    def sanitize_dns_label(value)
      value.to_s.downcase.gsub(/[^a-z0-9-]/, '-')
    end

    def build_dnsmasq_conf(domain, interface, server_ip, records, ttl)
      lines = []
      lines << '# Managed by messhy'
      lines << 'domain-needed'
      lines << 'bogus-priv'
      lines << "local=/#{domain}/"
      lines << "domain=#{domain}"
      lines << 'expand-hosts'
      lines << 'cache-size=1000'
      lines << "local-ttl=#{ttl}"
      lines << "interface=#{interface}"
      lines << 'bind-dynamic'
      lines << 'listen-address=127.0.0.1'
      lines << "listen-address=#{server_ip}"
      lines << ''

      records.sort.each do |hostname, ips|
        Array(ips).each do |ip|
          lines << "address=/#{hostname}/#{ip}"
        end
      end

      lines.join("\n") + "\n"
    end
  end
end
