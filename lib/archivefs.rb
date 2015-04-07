#!/usr/bin/env ruby
#encoding: utf-8

=begin
    Copyright 2015 Alex Belykh

    This file is part of ArchiveFS.

    ArchiveFS is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    ArchiveFS is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with ArchiveFS.  If not, see <http://www.gnu.org/licenses/>.
=end

require 'archivefs/version'

require 'pp'
require 'singleton'
require 'stringio'

require 'bundler/setup'
require 'rfusefs'
require 'zip/filesystem'

module ArchiveFS
  def self.full_split(path)
    dirname, basename = File.split(path)
    return [basename] if basename.eql?(path)
    full_split(dirname) << basename
  end

  class NormalDir
    attr_reader :root

    def initialize(root, parent = nil)
      @root = root
      @parent = parent
      @children = Hash.new do |h, path|
        child_prefix = h.keys.find do |p|
          path.start_with?(p)
        end
        if child_prefix
          h[child_prefix]
        else
          tail = ArchiveFS::full_split(path)
          head = []
          while tail.size > 0
            head << tail.shift
            head_path = File.join(*head)
            if is_archive?(head_path)
              break(h[head_path] = ZipDir.new(head_path, self))
            end
          end
        end
      end
    end

    def das_path(path)
      File.join(@root, path)
    end

    def is_archive?(path)
      do_file?(path) && path.end_with?('.zip')
    end

    def do_file?(path)
      File.file?(das_path(path))
    end

    def do_directory?(path)
      File.directory?(das_path(path))
    end

    def do_contents(path)
      Dir.entries(das_path(path))
    end

    def do_read_file(path)
      File.binread(das_path(path))
    end

    def do_size(path)
      File.size(das_path(path))
    end

    def contents(path)
      if do_directory?(path)
        do_contents(path)
      else
        child = @children[path]
        if child
          child.contents(path[child.root.size..-1])
        else
          []
        end
      end
    end

    def directory?(path)
      #pp Time.now
      if do_directory?(path)
        true
      else
        child = @children[path]
        if child
          child.directory?(path[child.root.size..-1])
        else
          false
        end
      end
    end

    def file?(path)
      child = @children[path]
      if child
        child.file?(path[child.root.size..-1])
      else
        do_file?(path)
      end
    end

    def read_file(path)
      if do_file?(path)
        do_read_file(path)
      else
        child = @children[path]
        if child
          child.read_file(path[child.root.size..-1])
        else
          ''
        end
      end
    end

    def do_raw_open(path, mode, rfusefs = nil)
      File.open(das_path(path), mode)
    end

    def raw_open(path, mode, rfusefs = nil)
      if do_file?(path)
        do_raw_open(path, mode, rfusefs)
      else
        child = @children[path]
        if child
          child.raw_open(path[child.root.size..-1], mode, rfusefs)
        else
          nil
        end
      end
    end

    def raw_read(path, offset, size, raw = nil)
      raw.seek(offset)
      raw.read(size)
    end

    def raw_close(path,raw=nil)
      raw.close
    end

    def do_executable?(path)
      File.executable?(das_path(path))
    end

    def do_exists?(path)
      File.exists?(das_path(path))
    end

    def executable?(path)
      if do_exists?(path)
        do_executable?(path)
      else
        child = @children[path]
        if child
          child.executable?(path[child.root.size..-1])
        else
          ''
        end
      end
    end

    def size(path)
      if do_file?(path)
        do_size(path)
      else
        child = @children[path]
        if child
          child.size(path[child.root.size..-1])
        else
          0
        end
      end
    end
  end

  class ZipDir < NormalDir
    def initialize(root, parent)
      super
      #io = ::StringIO.new(parent.read_file(root))
      #@zf = ::Zip::File.new('', true, true)
      #@zf.read_from_stream(io)
      @zf = ::Zip::File.new(File.join(parent.root, root))
    end

    def do_file?(path)
      @zf.file.file?(path)
    end

    def do_directory?(path)
      @zf.file.directory?(path)
    end

    def do_contents(path)
      @zf.dir.entries(path)
    end

    def do_read_file(path)
      @zf.file.read(path).force_encoding('BINARY')
    end

    def do_size(path)
      @zf.file.size(path)
    end

    def do_executable?(path)
      @zf.file.executable?(path)
    end

    def do_exists?(path)
      @zf.file.exists?(path)
    end

    def raw_open(path,mode,rfusefs = nil)
      nil
    end
  end

  require 'delegate'
  class DebugDelegator < SimpleDelegator
    def method_missing(name, *args, &block)
      res = super
      puts "#{name}(#{args.join(', ')}) -> #{res.inspect[0..100]}"
      res
    end

    def respond_to_missing?(name, include_private = false)
      res = super
      puts "?#{name} -> #{res.inspect}"
      res
    end
  end
end
