namespace :messhy do
  desc 'Install Messhy configuration'
  task :install do
    system('rails generate messhy:install')
  end

  desc 'Deploy WireGuard VPN mesh to all nodes'
  task :setup do
    system('bundle exec messhy setup')
  end

  desc 'Check VPN mesh connectivity'
  task :health do
    system('bundle exec messhy health')
  end

  desc 'Generate new WireGuard keys'
  task :keygen do
    system('bundle exec messhy keygen')
  end

  desc 'Show mesh status'
  task :status do
    puts "\n🔒 WireGuard VPN Mesh Status\n\n"
    system('bundle exec messhy status')
  end

  desc 'Trust SSH host keys for all nodes'
  task :trust_hosts do
    system('bundle exec messhy trust-hosts')
  end
end
