require "./**"
require "db"

File::Index::Logger.import

# TODO: Write documentation for `File::Index`
class File
  class Index
    VERSION = "0.1.0"
    @@hostname = System.hostname

    property dbfile : String
    property db : DB::Database

    def initialize(dbfile = "~/.cache/file-index-cr.sqlite3")
      @dbfile = File.real_path File.expand_path dbfile.to_s
      @db = DB.open("sqlite3://#{@dbfile}")
    end

    def by_id(id : Int)
      File::Index::Entry.by_id(id: id, db: @db)
    end

    def add(path : Path, checksum : Bool = false)
      self.add(path.to_s, checksum)
    end

    def add(path : String, checksum : Bool = false, hostname : String = @@hostname)
      debug "add(#{path.inspect}, checksum: #{checksum.inspect}, hostname: #{hostname.inspect})"
      entries = [] of File::Index::Entry
      queue = Deque(String).new(1000)
      queue.push path
      while queue.size > 0
        path = queue.shift
        entry = File::Index::Entry.new_from_filesystem db: @db, path: path, checksum: checksum
        entries << entry
        if entry.is_dir?
          Dir.children(path).each { |c| queue << "#{path}/#{c}" }
        end
      end
      entries
    end

    def all
      resultset = File::Index::Entry.db_where(@db)
      resultset.each do |result|
        yield File::Index::Entry.new_from_resultset(result)
      end
    end

    def all
      File::Index::Entry.find(@db)
    end

    def self.create_db(dbfile : String | Path)
      db = DB.open("sqlite3://#{dbfile}")
      db.exec %{CREATE TABLE IF NOT EXISTS entry (
        "id" INTEGER PRIMARY KEY,
        "hostname" TEXT NOT NULL,
        "dir" TEXT NOT NULL,
        "name" TEXT NOT NULL,
        "dev" INTEGER NOT NULL,
        "inode" INTEGER NOT NULL,
        "size" INTEGER NOT NULL,
        "permissions" INTEGER NOT NULL,
        "filetype" TEXT NOT NULL,
        "flags" TEXT NOT NULL,
        "mtime" INTEGER NOT NULL,
        "uid" INTEGER NOT NULL,
        "owner" TEXT NOT NULL,
        "gid" INTEGER NOT NULL,
        "group" TEXT NOT NULL,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        "crc32" TEXT DEFAULT NULL,
        "sha256" TEXT DEFAULT NULL,
        "link_target" TEXT DEFAULT NULL
      );}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_uid"         ON entry ("uid");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_owner"       ON entry ("owner");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_gid"         ON entry ("gid");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_group"       ON entry ("group");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_size"        ON entry ("size");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_mtime"       ON entry ("mtime");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_hostname"    ON entry ("hostname");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_permissions" ON entry ("permissions");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_dir"         ON entry ("dir");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_name"        ON entry ("name");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_dir_name"    ON entry ("dir", "name");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_updated_at"  ON entry ("updated_at");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_crc32"       ON entry ("crc32");}
      db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_sha256"      ON entry ("sha256");}

      db.exec %{CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dir_name  ON entry ("hostname", "dir", "name");}
      db.exec %{CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dev_inode ON entry ("hostname", "dev", "inode");}
    end

    def self.reset!(dbfile : String | Path)
      db = DB.open("sqlite3://#{dbfile}")
      db.exec("DELETE FROM entry;")
    end
  end
end
