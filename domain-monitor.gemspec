# frozen_string_literal: true

require_relative 'lib/domain_monitor/version'

Gem::Specification.new do |spec|
  spec.name          = 'domain-monitor'
  spec.version       = DomainMonitor::VERSION
  spec.authors       = ['KK']
  spec.email         = ['kk@example.com']

  spec.summary       = 'A Ruby domain expiration monitoring tool with Nacos integration'
  spec.description   = 'Monitor domain expiration dates using WHOIS protocol, with Nacos configuration center integration and Prometheus metrics export'
  spec.homepage      = 'https://github.com/yourusername/domain-monitor'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.0.0')

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  spec.files         = Dir.glob('{bin,lib}/**/*') + %w[LICENSE README.md]
  spec.bindir        = 'bin'
  spec.executables   = ['domain-monitor']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'dotenv', '~> 2.8'
  spec.add_dependency 'prometheus-client', '~> 4.1'
  spec.add_dependency 'puma', '~> 6.4'
  spec.add_dependency 'rack', '~> 2.2', '>= 2.2.4'
  spec.add_dependency 'sinatra', '~> 3.1'
  spec.add_dependency 'whois', '~> 5.1'
  spec.add_dependency 'whois-parser', '~> 2.0'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.57'
end
