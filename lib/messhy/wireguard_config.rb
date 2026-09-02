# frozen_string_literal: true

module Messhy
  class WireguardConfig
    attr_reader :interface, :peers

    def self.parse(content)
      new(content).tap(&:parse!)
    end

    def initialize(content)
      @content = content
      @interface = {}
      @peers = []
    end

    def parse!
      section = nil
      peer_name = nil

      @content.each_line do |line|
        stripped = line.strip
        if (match = stripped.match(/\A# Peer: (.+)\z/))
          peer_name = match[1]
        elsif stripped == '[Interface]'
          section = interface
        elsif stripped == '[Peer]'
          section = {}
          section['Name'] = peer_name if peer_name
          peers << section
          peer_name = nil
        elsif section && (match = stripped.match(/\A([^#=]+?)\s*=\s*(.+)\z/))
          section[match[1].strip] = match[2].strip
        end
      end

      self
    end

    def preserve_unmanaged_peers_in(candidate_content, managed_peer_names:)
      candidate = self.class.parse(candidate_content)
      candidate_public_keys = candidate.peers.filter_map { |peer| peer['PublicKey'] }
      managed_peer_names = managed_peer_names.to_set

      unmanaged_peers = peers.reject do |peer|
        managed_peer_names.include?(peer['Name']) || candidate_public_keys.include?(peer['PublicKey'])
      end

      return candidate_content if unmanaged_peers.empty?

      [candidate_content.rstrip, *unmanaged_peers.map { |peer| render_peer(peer) }, ''].join("\n\n")
    end

    private

    def render_peer(peer)
      lines = []
      lines << "# Peer: #{peer['Name']}" if peer['Name']
      lines << '[Peer]'
      peer.each do |key, value|
        next if key == 'Name'

        lines << "#{key} = #{value}"
      end
      lines.join("\n")
    end
  end
end
