require_relative 'lib/messhy/version'

Gem::Specification.new do |spec|
  spec.name = 'messhy'
  spec.version = Messhy::VERSION
  spec.authors = ['BoringCache']
  spec.email = ['oss@boringcache.com']

  spec.summary = 'WireGuard VPN mesh for Ruby & Rails apps'
  spec.description = 'Sets up a full WireGuard VPN mesh across any VMs. ' \
                     'Every node connects directly to every other node for secure private networking.'
  spec.homepage = 'https://github.com/boringcache/messhy'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0.0'

  spec.metadata['source_code_uri'] = 'https://github.com/boringcache/messhy'
  spec.metadata['documentation_uri'] = 'https://github.com/boringcache/messhy/blob/main/README.md'
  spec.metadata['changelog_uri'] = 'https://github.com/boringcache/messhy/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/boringcache/messhy/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob(%w[
                          lib/**/*.rb
                          lib/**/*.rake
                          templates/**/*
                          exe/*
                          CHANGELOG.md
                          LICENSE
                          README.md
                          SECURITY.md
                        ])
  spec.bindir = 'exe'
  spec.executables = ['messhy']
  spec.require_paths = ['lib']

  spec.add_dependency 'bcrypt_pbkdf', '~> 1.1'
  spec.add_dependency 'ed25519', '~> 1.4'
  spec.add_dependency 'sshkit', '~> 1.25'
  spec.add_dependency 'thor', '~> 1.5'
end
