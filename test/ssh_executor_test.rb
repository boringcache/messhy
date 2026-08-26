require 'test_helper'

class SSHExecutorTest < Minitest::Test
  def test_target_can_connect_through_a_declared_jump_host
    ssh_key = File::NULL
    config_hash = {
      'test' => {
        'user' => 'ubuntu',
        'ssh_key' => ssh_key,
        'verify_host_key' => 'accept_new',
        'nodes' => {
          'jump' => { 'host' => '1.2.3.4', 'private_ip' => '10.8.0.1' },
          'target' => { 'host' => '5.6.7.8', 'private_ip' => '10.8.0.2', 'jump_host' => 'jump' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    executor = Messhy::SSHExecutor.new(config)

    host = executor.send(:host_for, 'target', config.node_config('target'))
    proxy = host.ssh_options.fetch(:proxy)

    assert_instance_of Net::SSH::Proxy::Command, proxy
    assert_includes proxy.command_line_template, 'ssh -F /dev/null'
    assert_includes proxy.command_line_template, '-o BatchMode\\=yes'
    assert_includes proxy.command_line_template, '-o ForwardAgent\\=no'
    assert_includes proxy.command_line_template, '-o StrictHostKeyChecking\\=accept-new'
    assert_includes proxy.command_line_template, "-i #{ssh_key}"
    assert_includes proxy.command_line_template, '-o IdentitiesOnly\\=yes'
    assert_includes proxy.command_line_template, '-W %h:%p ubuntu@1.2.3.4'
  end

  def test_direct_node_does_not_receive_a_proxy
    config_hash = {
      'test' => {
        'nodes' => {
          'direct' => { 'host' => '1.2.3.4', 'private_ip' => '10.8.0.1' }
        }
      }
    }
    config = Messhy::Configuration.new(config_hash, 'test')
    executor = Messhy::SSHExecutor.new(config)

    host = executor.send(:host_for, 'direct', config.node_config('direct'))

    refute host.ssh_options&.key?(:proxy)
  end
end
