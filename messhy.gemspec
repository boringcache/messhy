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
  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/boringcache/messhy'
  spec.metadata['documentation_uri'] = 'https://github.com/boringcache/messhy/blob/main/README.md'
  spec.metadata['changelog_uri'] = 'https://github.com/boringcache/messhy/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob(%w[
                          lib/**/*.rb
                          templates/**/*
                          exe/*
                          LICENSE
                          README.md
                        ])
  spec.bindir = 'exe'
  spec.executables = ['messhy']
  spec.require_paths = ['lib']

  spec.add_dependency 'bcrypt_pbkdf', '~> 1.1'
  spec.add_dependency 'ed25519', '~> 1.3'
  spec.add_dependency 'sshkit', '~> 1.21'
  spec.add_dependency 'thor', '~> 1.3'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'simplecov', '~> 0.22'
end
