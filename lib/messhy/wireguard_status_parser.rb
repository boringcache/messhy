# frozen_string_literal: true

module Messhy
  module WireguardStatusParser
    TIME_UNITS_IN_SECONDS = {
      'second' => 1,
      'minute' => 60,
      'hour' => 3_600,
      'day' => 86_400
    }.freeze

    module_function

    def extract_peer_block(status, target_ip)
      status.split('peer:').drop(1).find do |block|
        block.include?("allowed ips: #{target_ip}/32")
      end
    end

    def parse_handshake_seconds(desc)
      return nil if desc.strip.casecmp('(none)').zero?

      matches = desc.scan(/(\d+)\s+(second|minute|hour|day)s?/i)
      return nil if matches.empty?

      matches.sum do |value, unit|
        TIME_UNITS_IN_SECONDS[unit.downcase] * value.to_i
      end
    end

    def extract_handshake_time(peer_block)
      return nil unless peer_block

      desc = peer_block[/latest handshake:\s*(.+)/, 1]
      return nil unless desc&.include?('ago')

      parse_handshake_seconds(desc)
    end

    def extract_transfer_stats(peer_block)
      rx = peer_block.match(/transfer: (.+?) received/)&.[](1) || '0 B'
      tx = peer_block.match(/received, (.+?) sent/)&.[](1) || '0 B'
      { received: rx, sent: tx }
    end

    def extract_endpoint(peer_block)
      peer_block[/endpoint: (.+?)$/, 1]
    end

    def extract_allowed_ips(peer_block)
      peer_block[/allowed ips: (.+?)$/, 1]
    end
  end
end
