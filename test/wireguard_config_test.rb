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
end
