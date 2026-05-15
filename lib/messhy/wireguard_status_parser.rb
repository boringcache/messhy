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

      total = 0
      words = desc.downcase.delete(',').split

      words.each_cons(2) do |value, unit|
        unit = unit.delete_suffix('s')
        next unless integer_token?(value) && TIME_UNITS_IN_SECONDS.key?(unit)

        total += TIME_UNITS_IN_SECONDS.fetch(unit) * value.to_i
      end

      total.positive? ? total : nil
    end

    def extract_handshake_time(peer_block)
      return nil unless peer_block

      desc = line_value(peer_block, 'latest handshake: ')
      return nil unless desc&.include?('ago')

      parse_handshake_seconds(desc)
    end

    def extract_transfer_stats(peer_block)
      transfer = line_value(peer_block, 'transfer: ')
      rx, tx = transfer ? transfer.split(' received, ', 2) : nil
      tx = tx&.delete_suffix(' sent')

      { received: rx || '0 B', sent: tx || '0 B' }
    end

    def extract_endpoint(peer_block)
      line_value(peer_block, 'endpoint: ')
    end

    def extract_allowed_ips(peer_block)
      line_value(peer_block, 'allowed ips: ')
    end

    def line_value(block, prefix)
      block.each_line(chomp: true).find { |line| line.start_with?(prefix) }&.delete_prefix(prefix)
    end

    def integer_token?(value)
      !value.empty? && value.each_char.all? { |char| char >= '0' && char <= '9' }
    end
  end
end
