# frozen_string_literal: true

require_relative 'lib/gl_report/version'

Gem::Specification.new do |spec|
  spec.name        = 'gl_report'
  spec.version     = GlReport::VERSION
  spec.authors     = ['Tim Lawrenz']
  spec.email       = ['tim@givelively.org']

  spec.summary     = 'A flexible reporting DSL'
  spec.description = 'Generate SQL-optimized reports with support for virtual columns and complex filtering'
  spec.homepage    = 'https://github.com/givelively/gl_report'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir[
    'lib/**/*',
    'LICENSE.txt',
    'README.md',
    'CHANGELOG.md'
  ]

  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 6.0'
  spec.add_dependency 'activesupport', '>= 6.0'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.21'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.0'
end
