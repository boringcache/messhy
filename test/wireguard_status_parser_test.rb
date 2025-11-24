require 'test_helper'

class WireguardStatusParserTest < Minitest::Test
  def test_parse_handshake_seconds_with_single_unit
    assert_equal 30, Messhy::WireguardStatusParser.parse_handshake_seconds('30 seconds ago')
    assert_equal 120, Messhy::WireguardStatusParser.parse_handshake_seconds('2 minutes ago')
    assert_equal 7200, Messhy::WireguardStatusParser.parse_handshake_seconds('2 hours ago')
    assert_equal 172_800, Messhy::WireguardStatusParser.parse_handshake_seconds('2 days ago')
  end

  def test_parse_handshake_seconds_with_multiple_units
    result = Messhy::WireguardStatusParser.parse_handshake_seconds('1 day 2 hours 30 minutes ago')
    expected = 86_400 + 7_200 + 1_800 # 1 day + 2 hours + 30 minutes
    assert_equal expected, result
  end

  def test_parse_handshake_seconds_with_singular_and_plural
    assert_equal 1, Messhy::WireguardStatusParser.parse_handshake_seconds('1 second ago')
    assert_equal 60, Messhy::WireguardStatusParser.parse_handshake_seconds('1 minute ago')
  end

  def test_parse_handshake_seconds_returns_nil_for_none
    assert_nil Messhy::WireguardStatusParser.parse_handshake_seconds('(none)')
    assert_nil Messhy::WireguardStatusParser.parse_handshake_seconds('  (NONE)  ')
  end

  def test_parse_handshake_seconds_returns_nil_for_invalid
    assert_nil Messhy::WireguardStatusParser.parse_handshake_seconds('invalid')
    assert_nil Messhy::WireguardStatusParser.parse_handshake_seconds('')
  end

  def test_extract_peer_block
    status = <<~STATUS
      interface: wg0
      peer: ABC123
      allowed ips: 10.8.0.2/32
      transfer: 100 MiB received, 50 MiB sent
      peer: DEF456
      allowed ips: 10.8.0.3/32
      transfer: 200 MiB received, 100 MiB sent
    STATUS

    peer_block = Messhy::WireguardStatusParser.extract_peer_block(status, '10.8.0.3')
    assert_includes peer_block, 'DEF456'
    assert_includes peer_block, '200 MiB received'
  end

  def test_extract_handshake_time
    peer_block = <<~PEER
      peer: ABC123
      latest handshake: 30 seconds ago
      transfer: 100 MiB received, 50 MiB sent
    PEER

    result = Messhy::WireguardStatusParser.extract_handshake_time(peer_block)
    assert_equal 30, result
  end

  def test_extract_handshake_time_returns_nil_when_no_block
    assert_nil Messhy::WireguardStatusParser.extract_handshake_time(nil)
  end

  def test_extract_handshake_time_returns_nil_when_none
    peer_block = <<~PEER
      peer: ABC123
      latest handshake: (none)
      transfer: 100 MiB received, 50 MiB sent
    PEER

    assert_nil Messhy::WireguardStatusParser.extract_handshake_time(peer_block)
  end

  def test_extract_transfer_stats
    peer_block = <<~PEER
      peer: ABC123
      transfer: 100 MiB received, 50 MiB sent
    PEER

    stats = Messhy::WireguardStatusParser.extract_transfer_stats(peer_block)
    assert_equal '100 MiB', stats[:received]
    assert_equal '50 MiB', stats[:sent]
  end

  def test_extract_transfer_stats_defaults_to_zero
    peer_block = 'peer: ABC123'

    stats = Messhy::WireguardStatusParser.extract_transfer_stats(peer_block)
    assert_equal '0 B', stats[:received]
    assert_equal '0 B', stats[:sent]
  end

  def test_extract_endpoint
    peer_block = <<~PEER
      peer: ABC123
      endpoint: 1.2.3.4:51820
      transfer: 100 MiB received, 50 MiB sent
    PEER

    endpoint = Messhy::WireguardStatusParser.extract_endpoint(peer_block)
    assert_equal '1.2.3.4:51820', endpoint
  end

  def test_extract_allowed_ips
    peer_block = <<~PEER
      peer: ABC123
      allowed ips: 10.8.0.2/32
      transfer: 100 MiB received, 50 MiB sent
    PEER

    allowed_ips = Messhy::WireguardStatusParser.extract_allowed_ips(peer_block)
    assert_equal '10.8.0.2/32', allowed_ips
  end
end
