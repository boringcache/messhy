require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
  add_group 'Core', 'lib/messhy'
end

begin
  require 'bundler/setup'
rescue StandardError => e
  warn "Skipping bundler/setup: #{e.message}" if ENV['VERBOSE']
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'messhy'
require 'minitest/autorun'
