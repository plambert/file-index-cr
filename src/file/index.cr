require "./**"
require "db"

File::Index::Logger.import

class File
  class Index
    VERSION = "0.1.0"
    property hostname : String = System.hostname
    property default_checksum_mode : ChecksumMode = ChecksumMode::MODIFIED_ONLY
    property dbfile : String
    property db : DB::Database { DB.open "sqlite3://#{@dbfile}" }
    property show_progress : Bool = true

    def initialize(dbfile = "~/.cache/file-index-cr.sqlite3")
      @dbfile = File.real_path File.expand_path dbfile.to_s
    end

    def by_id(id : UInt64)
      File::Index::Entry.by_id(id: id, db: self.db)
    end

    def find(where : String? = nil, *args, limit : Int? = nil)
      debug "find(#{where.inspect}, #{args}) do ... end"
      raise "#{limit}: limit must be a positive, non-zero integer" if limit && limit < 1
      sql_command = String.build(200_i32 + (where ? where.size : 0)) do |str|
        str << "SELECT \"id\", #{File::Index::Entry.properties.map { |p| "\"#{p}\"" }.join(", ")} FROM entry"
        if where
          str << " WHERE #{where}"
        end
        str << " ORDER BY hostname, dir, name"
        if limit
          str << " LIMIT #{limit}"
        end
        str << ";"
      end
      debug "SQL: %s", sql_command
      db.query(sql_command, *args) do |rs|
        rs.each do
          yield File::Index::Entry.from_resultset(rs)
        end
      end
    end

    def find(where : String? = nil, *args, limit : Int? = nil) : Array(File::Index::Entry)
      debug "find(#{where.inspect}, #{args})"
      list = [] of File::Index::Entry
      self.find(where, *args, limit: limit) { |entry| list << entry }
      list
    end

    def find_one(where : String, *args) : File::Index::Entry
      debug "find_one(#{where.inspect}, #{args})"
      result = self.find(where, *args, limit: 1)
      result.first
    end

    def find_one?(where : String, *args)
      debug "find_one?(#{where.inspect}, #{args})"
      result = self.find_one(where, *args)
      result.first
    rescue
      nil
    end

    def by_id(id : Int)
      debug "by_id(#{id.inspect})"
      self.find_one("id=?", id)
    end

    def by_id?(id : Int)
      debug "by_id?(#{id.inspect})"
      self.by_id(id)
    rescue
      nil
    end

    def [](id : Int)
      self.by_id(id)
    end

    def []?(id : Int)
      self.by_id?(id)
    end

    def by_path(path : Path | String, hostname : String = @hostname)
      debug "by_path(#{path.inspect}, #{hostname.inspect})"
      dirname = File.dirname path.to_s
      basename = File.basename path.to_s
      self.find_one("hostname=? AND dir=? AND name=?", hostname, dirname, basename)
    end

    def [](path : Path | String)
      self.by_path(path: path, hostname: @hostname)
    end

    def []?(path : Path | String)
      self.by_path(path: path, hostname: @hostname)
    rescue
      nil
    end

    def add(path : Path, checksum_mode : ChecksumMode = @default_checksum_mode, hostname : String = @hostname)
      self.add(path.to_s, checksum_mode: checksum_mode, hostname: hostname)
    end

    def add(path : String, checksum_mode : ChecksumMode = @default_checksum_mode, hostname : String = @hostname, start_time = Time.local)
      debug "add(#{path.inspect}, checksum_mode: #{checksum_mode}, hostname: #{hostname.inspect})"
      entries = [] of File::Index::Entry
      queue = Deque(String).new(1000)
      queue.push path
      while queue.size > 0
        path = queue.shift
        entry = self.add_one path: path, checksum_mode: checksum_mode, hostname: hostname, start_time: start_time
        entries << entry
        if entry.directory?
          Dir.children(path).each { |c| queue << "#{path}/#{c}" }
        end
      end
      entries
    end

    def add_one(path : String, checksum_mode : ChecksumMode = @default_checksum_mode, hostname : String = @hostname, start_time = Time.local)
      debug "add_one(#{path.inspect}, checksum_mode: #{checksum_mode}, hostname: #{hostname.inspect})"
      self.new_from_filesystem path: path, checksum_mode: checksum_mode, hostname: hostname, start_time: start_time
    end

    def all
      resultset = File::Index::Entry.find(self.db) do |result|
        yield File::Index::Entry.new_from_resultset(result)
      end
    end

    def all
      self.find
    end

    def new_from_filesystem(path : Path | String, hostname : String = @hostname, checksum_mode : ChecksumMode = @default_checksum_mode, start_time : Time = Time.local) : File::Index::Entry
      debug "new_from_filesystem(path: #{path.inspect}, checksum_mode: #{checksum_mode}, hostname: #{hostname})"
      if File.exists? path
        path = File.real_path File.expand_path path.to_s
      elsif File.exists? File.dirname(path)
        path = sprintf "%s/%s", File.real_path(File.expand_path(File.dirname(path))), File.basename(path)
        warn "%s: dangling symlink", path
      else
        raise "#{path}: parent directory does not exist"
      end
      new_entry : File::Index::Entry
      begin
        new_entry = self.by_path(path, hostname)
        debug "  found: #{new_entry.inspect}"
        raise "no new entry" unless new_entry
      rescue e
        debug "  not found: creating new: #{e.inspect}"
        info = File.info(path.to_s, follow_symlinks: false)
        new_entry = File::Index::Entry.new(
          hostname: hostname,
          dir: File.dirname(path),
          name: File.basename(path),
          dev: info.dev.to_i32,
          inode: info.inode.to_i32,
          size: info.size.to_i64,
          mtime: info.modification_time,
          permissions: info.permissions,
          filetype: info.type,
          flags: info.flags,
          uid: info.owner.to_i32,
          owner: self.class.username(info.owner),
          gid: info.group.to_i32,
          group: self.class.groupname(info.group),
          updated_at: Time.utc,
          created_at: Time.utc,
          crc32: nil,
          sha256: nil,
          link_target: info.symlink? ? File.readlink(path) : nil,
        )
        debug "  new: #{new_entry.inspect}"
      end
      new_entry.calculate_checksums checksum_mode: checksum_mode, start_time: start_time
      new_entry.update(db)
      new_entry
    end

    def self.groupname(gid)
      System::Group.find_by(id: gid.to_s).name
    rescue
      "GID\##{gid}"
    end

    def self.username(uid)
      System::User.find_by(id: uid.to_s).username
    rescue
      "UID\##{uid}"
    end

    def self.create_db(dbfile : String | Path)
      db = DB.open("sqlite3://#{dbfile}")
      File::Index::SQL.apply(db)
      # db.exec %{CREATE TABLE IF NOT EXISTS entry (
      #   "id" INTEGER PRIMARY KEY,
      #   "hostname" TEXT NOT NULL,
      #   "dir" TEXT NOT NULL,
      #   "name" TEXT NOT NULL,
      #   "dev" INTEGER NOT NULL,
      #   "inode" INTEGER NOT NULL,
      #   "size" INTEGER NOT NULL,
      #   "permissions" INTEGER NOT NULL,
      #   "filetype" TEXT NOT NULL,
      #   "flags" TEXT NOT NULL,
      #   "mtime" INTEGER NOT NULL,
      #   "uid" INTEGER NOT NULL,
      #   "owner" TEXT NOT NULL,
      #   "gid" INTEGER NOT NULL,
      #   "group" TEXT NOT NULL,
      #   "created_at" INTEGER NOT NULL,
      #   "updated_at" INTEGER NOT NULL,
      #   "crc32" TEXT DEFAULT NULL,
      #   "sha256" TEXT DEFAULT NULL,
      #   "link_target" TEXT DEFAULT NULL
      # );}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_uid"         ON entry ("uid");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_owner"       ON entry ("owner");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_gid"         ON entry ("gid");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_group"       ON entry ("group");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_size"        ON entry ("size");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_mtime"       ON entry ("mtime");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_hostname"    ON entry ("hostname");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_permissions" ON entry ("permissions");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_dir"         ON entry ("dir");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_name"        ON entry ("name");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_dir_name"    ON entry ("dir", "name");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_updated_at"  ON entry ("updated_at");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_crc32"       ON entry ("crc32");}
      # db.exec %{CREATE INDEX IF NOT EXISTS "idx_entry_sha256"      ON entry ("sha256");}

      # db.exec %{CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dir_name  ON entry ("hostname", "dir", "name");}
      # db.exec %{CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dev_inode ON entry ("hostname", "dev", "inode");}
    end

    def self.reset!(dbfile : String | Path)
      db = DB.open("sqlite3://#{dbfile}")
      db.exec("DELETE FROM entry;")
    end
  end
end
