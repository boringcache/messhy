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
  end
end
