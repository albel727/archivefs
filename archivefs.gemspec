# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'archivefs/version'

Gem::Specification.new do |spec|
  spec.name          = 'archivefs'
  spec.version       = ArchiveFS::VERSION
  spec.authors       = ['Alex Belykh']
  spec.email         = ['albel727@ngs.ru']
  spec.summary       = %q{ArchiveFS is a bulk archive-as-directory Fuse-based filesystem.}
  spec.description   = %q{ArchiveFS transparently presents all archives under a given directory
as directories, so that their contents can be browsed without manual extraction.
It's different from other "archive mounters" in this regard,
since it isn't limited to a single archive file.}
  spec.homepage      = 'https://github.com/albel727/archivefs'
  spec.license       = 'GPLv3'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'rfusefs', '~> 1.0', '>= 1.0.3'
  spec.add_dependency 'rubyzip', '~> 1.1', '>= 1.1.7'
  spec.add_dependency 'rchardet', '~> 1.6', '>= 1.6.0'
  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
end
