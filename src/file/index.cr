require "sqlite3"

# TODO: Write documentation for `File::Index`
class File::Index
  VERSION = "0.1.0"
  property dbfile : String
  property db : DB::Database

  def initialize(@dbfile = "./file-index.sqlite3")
    @db = DB.open "sqlite3://./#{@dbfile}"
  end

  def by_id(id : UInt64)
    File::Entry.new(id, @db)
  end

  def add(path : String)
    self.add(File.new(path))
  end

  def add(path : File)
    entries = [] of File::Entry
    queue = [path]
    while queue.size > 0
      entry = queue.shift
      if entry.is_file?
        entries << File::Entry.new(entry, @db)
      end
    end
  end
end
