require 'test_helper'

class WireguardConfigTest < Minitest::Test
  def test_parses_interface_and_named_peers
    config = Messhy::WireguardConfig.parse(<<~CONFIG)
      [Interface]
      Address = 10.8.0.1/24
      PrivateKey = private-one

      # Peer: node-two
      [Peer]
      PublicKey = public-two
      PresharedKey = shared-key
      AllowedIPs = 10.8.0.2/32
    CONFIG

    assert_equal '10.8.0.1/24', config.interface.fetch('Address')
    assert_equal 'private-one', config.interface.fetch('PrivateKey')
    assert_equal 'node-two', config.peers.first.fetch('Name')
    assert_equal 'shared-key', config.peers.first.fetch('PresharedKey')
  end

  def test_preserves_peers_outside_the_managed_mesh
    current = Messhy::WireguardConfig.parse(<<~CONFIG)
      [Interface]
      Address = 10.8.0.1/24

      # Peer: node-two
      [Peer]
      PublicKey = old-public-two
      AllowedIPs = 10.8.0.2/32

      # Peer: external-builder
      [Peer]
      PublicKey = external-public
      PresharedKey = external-shared-key
      AllowedIPs = 10.8.0.20/32
      Endpoint = 203.0.113.20:51820
    CONFIG
    candidate = <<~CONFIG
      [Interface]
      Address = 10.8.0.1/24

      # Peer: node-two
      [Peer]
      PublicKey = new-public-two
      AllowedIPs = 10.8.0.2/32
      Endpoint = 10.0.0.2:51820
    CONFIG

    merged = current.preserve_unmanaged_peers_in(candidate, managed_peer_names: ['node-two'])

    assert_includes merged, 'PublicKey = new-public-two'
    refute_includes merged, 'PublicKey = old-public-two'
    assert_includes merged, '# Peer: external-builder'
    assert_includes merged, 'PresharedKey = external-shared-key'
    assert_includes merged, 'Endpoint = 203.0.113.20:51820'
  end

  def test_does_not_duplicate_an_unnamed_peer_already_in_the_candidate
    current = Messhy::WireguardConfig.parse(<<~CONFIG)
      [Interface]
      Address = 10.8.0.1/24

      [Peer]
      PublicKey = shared-public
      AllowedIPs = 10.8.0.2/32
    CONFIG
    candidate = <<~CONFIG
      [Interface]
      Address = 10.8.0.1/24

      # Peer: node-two
      [Peer]
      PublicKey = shared-public
      AllowedIPs = 10.8.0.2/32
    CONFIG

    merged = current.preserve_unmanaged_peers_in(candidate, managed_peer_names: ['node-two'])

    assert_equal 1, merged.scan('PublicKey = shared-public').size
  end
end
