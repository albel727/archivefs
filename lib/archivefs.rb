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
require 'rchardet'
require 'rfusefs'
require 'zip/filesystem'

module ArchiveFS
  FILESYSTEM_ENCODING = Encoding.find('filesystem')
  BINARY_ENCODING = Encoding.find('binary')

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

    # Returns array of arrays with contents for all directories.
    def self.recursive_entries(f, d, parent = '/')
      return [] unless f.directory?(parent)
      e = d.entries(parent)
      e.flat_map do |en|
        recursive_entries(f, d, f.join(parent, en))
      end << e
    end

    def initialize(root, parent)
      super
      #io = ::StringIO.new(parent.read_file(root))
      #@zf = ::Zip::File.new('', true, true)
      #@zf.read_from_stream(io)
      @zf = ::Zip::File.new(File.join(parent.root, root))

      all_entries = ZipDir::recursive_entries(@zf.file, @zf.dir)

      # All zip entries should remain binary-encoded. They actually are,
      # but the rubyzip lib fails to preserve this fact by concatenating
      # them with empty strings and slashes, encoded with Ruby's default
      # encoding (normally UTF-8), and if the result looks sufficiently
      # like UTF-8, so becomes the resulting encoding. This leads
      # @zf.dir.entries() to returning a mix of ASCII-8BIT
      # (where the result happened to not look like UTF-8)
      # and UTF-8 strings. Let's make everything back into ASCII-8BIT.
      all_entries = all_entries.map do |dir|
        dir.map do |e|
          e.dup.force_encoding(BINARY_ENCODING)
        end
      end

      # Attempt to detect encoding from all filenames concatenated
      @encoding = CharDet.detect(all_entries.flatten(1).join)['encoding']

      @name_fs_to_zip = {}
      @name_zip_to_fs = {}

      # Populate maps with all existing parts.
      all_entries.each do |dir|
        trans_dir = dir.map do |path_component|
          # This may throw an exception, if we detected encoding incorrectly.
          transcoded_component = transcode_component_zip_to_fs(path_component)
          next path_component if transcoded_component.eql?(path_component)
          @name_fs_to_zip[transcoded_component] = path_component
          @name_zip_to_fs[path_component] = transcoded_component
        end

        # Detect if undefined character replacement during
        # transcoding conflated some names within a directory.
        unless dir.size == trans_dir.uniq.size
          raise 'Transcoding led to name ambiguity'
        end
      end
    end

    def do_file?(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.file?(path)
    end

    def do_directory?(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.directory?(path)
    end

    def do_contents(path)
      path = transcode_path_fs_to_zip(path)
      @zf.dir.entries(path).map {|f| transcode_component_zip_to_fs(f)}
    end

    def do_read_file(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.read(path).force_encoding(BINARY_ENCODING)
    end

    def do_size(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.size(path)
    end

    def do_executable?(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.executable?(path)
    end

    def do_exists?(path)
      path = transcode_path_fs_to_zip(path)
      @zf.file.exists?(path)
    end

    def raw_open(path,mode,rfusefs = nil)
      nil
    end

    private

    def transcode_component_zip_to_fs(path_component)
      # Force binary encoding, since the map has binary keys only.
      path_component = path_component.dup.force_encoding(BINARY_ENCODING)
      @name_zip_to_fs[path_component] ||
          path_component.encode(
              FILESYSTEM_ENCODING,
              @encoding,
              :undef => :replace,
          )
    end

    def transcode_component_fs_to_zip(path_component)
      @name_fs_to_zip[path_component] ||
          path_component.encode(
              @encoding,
              :undef => :replace,
              :invalid => :replace,
          ).dup.force_encoding(BINARY_ENCODING)
    end

    def transcode_path_fs_to_zip(path)
      @zf.file.join(*ArchiveFS::full_split(path).map do |path_component|
        transcode_component_fs_to_zip(path_component)
      end)
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
