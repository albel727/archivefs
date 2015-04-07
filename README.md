# ArchiveFS

ArchiveFS transparently presents all archives under a given directory as directories, so that their contents can be browsed without manual extraction.
It's different from other "archive mounters" in this regard, since it isn't limited to a single archive file.

It's just a sloppy implementation from ready-made parts, that I quickly slapped together, out of despair with MPD's zip file support.
Only zip archives with .zip extension are supported at the moment, and reads cause whole files to be extracted.

The encoding of filenames in zip files is attempted to be guessed and transcoded to the system-wide filesystem encoding.
Failure to do so presently means that the archive can't be browsed at all.

## Installation

    $ gem install archivefs

## Usage

Run `mount.archivefs -h` for usage options.
Generally it should behave like any other mount program.
Typical usage is

    $ mount.archivefs /directory_with_archives /mountpoint [-o options]

## Contributing

1. Fork it ( https://github.com/[my-github-username]/archivefs/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
