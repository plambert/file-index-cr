require "./**"
require "system/user"
require "system/group"
require "db"
require "sqlite3"
require "json"
require "crc32"
require "openssl"

File::Index::Logger.import

class File
  class Index
    class Entry
      @@properties = %w{hostname dir name dev inode size permissions filetype flags mtime uid owner gid group created_at updated_at crc32 sha256 link_target}
      @@hostname = System.hostname
      property id : Int64?
      property hostname : String
      property dir : String
      property name : String
      property dev : Int32?
      property inode : Int32?
      property size : Int64?
      property permissions : File::Permissions
      property filetype : File::Type?
      property flags : File::Flags?
      property mtime : Time?
      property uid : Int32?
      property owner : String?
      property gid : Int32?
      property group : String?
      property created_at : Time?
      property updated_at : Time?
      @crc32 : String? = nil
      @sha256 : String? = nil
      property link_target : String?

      def initialize(
        @hostname,
        @dir,
        @name,
        @dev = nil,
        @inode = nil,
        @size = nil,
        @permissions = nil,
        @filetype = nil,
        @flags = nil,
        @mtime = nil,
        @uid = nil,
        @owner = nil,
        @gid = nil,
        @group = nil,
        @created_at = nil,
        @updated_at = nil,
        @crc32 = nil,
        @sha256 = nil,
        @link_target = nil,
        @id = nil
      )
      end

      def local_info(hostname : String = @@hostname)
        if self.hostname == hostname
          File.info(self.path.to_s, follow_symlinks = false)
        else
          raise File::Index::Exception::WrongHost.new(wrong: self, local: hostname)
        end
      end

      def path
        Path.new(self.dir, self.name)
      end

      def self.new_from_filesystem(db : DB::Database, path : Path | String, hostname : String = @@hostname, checksum : Bool = false) : self
        debug "new_from_filesystem(#{path.inspect})"
        if File.exists? path
          path = File.real_path File.expand_path path.to_s
        elsif File.exists? File.dirname(path)
          path = sprintf "%s/%s", File.real_path(File.expand_path(File.dirname(path))), File.basename(path)
          warn "%s: dangling symlink", path
        else
          raise "#{path}: parent directory does not exist"
        end
        new_entry : self
        begin
          new_entry = self.by_path(db, path, hostname)
          debug "  found: #{new_entry.inspect}"
          raise "no new entry" unless new_entry
        rescue e
          debug "  not found: creating new: #{e.inspect}"
          info = File.info(path.to_s, follow_symlinks: false)
          new_entry = self.new(
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
            owner: self.username(info.owner),
            gid: info.group.to_i32,
            group: self.groupname(info.group),
            updated_at: Time.utc,
            created_at: Time.utc,
            crc32: nil,
            sha256: nil,
            link_target: info.symlink? ? File.readlink(path) : nil,
          )
          debug "  new: #{new_entry.inspect}"
        end
        new_entry.calculate_checksums if checksum
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

      def update_from_filesystem(db : DB::Database, hostname : String = @@hostname, checksum : Bool = false, checksum_if_changed : Bool = false)
        debug "update_from_filesystem() - #{self.inspect}"
        info = self.local_info hostname: hostname
        if (self.size != info.size) || (self.mtime != info.modification_time)
          if checksum_if_changed
            checksum = true
          else
            @sha256 = nil
            @crc32 = nil
          end
        end
        self.dev = info.dev.to_i32
        self.inode = info.inode
        self.size = info.size.to_i64
        self.permissions = info.permissions
        self.filetype = info.type
        self.flags = info.flags
        self.mtime = info.modification_time
        self.uid = info.owner
        self.owner = System::User.find_by(id: info.owner.to_s).username
        self.gid = info.group
        self.group = System::Group.find_by(id: info.group.to_s).name
        self.updated_at = Time.utc
        self.created_at = self.updated_at if self.created_at.nil?
        self.calculate_checksums force: true if checksum
        self.update(db)
      end

      def update(db : DB::Database)
        debug "update() - #{self.inspect}"
        @created_at = Time.utc if @created_at.nil?
        @updated_at = Time.utc if @updated_at.nil?
        if @mtime.nil?
          raise "nil mtime, wtf?"
          mtime = Time.utc
        end
        if @id.nil?
          sql_command = "INSERT INTO entry (%s) VALUES (%s);" % [
            @@properties.map { |p| "\"#{p}\"" }.join(", "),
            @@properties.map { |e| "?" }.join(", "),
          ]
          result = db.exec(sql_command, @hostname, @dir, @name, @dev, @inode, @size, @permissions.value.to_i64,
            @filetype.to_s, @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @created_at.as(Time).to_unix, @updated_at.as(Time).to_unix, @crc32, @sha256, @link_target)
          @id = result.last_insert_id.as(Int64)
        else
          sql_command = "UPDATE entry SET dev=?, inode=?, size=?, permissions=?, filetype=?, flags=?, mtime=?, uid=?, owner=?, gid=?, \"group\"=?, updated_at=?, crc32=?, sha256=?, link_target=? WHERE id=?;"
          result = db.exec(sql_command, @dev, @inode, @size, @permissions.value.to_i64, @filetype.to_s,
            @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @updated_at.as(Time).to_unix, @crc32, @sha256, @link_target)
        end
        self
      end

      def self.from_resultset(result)
        begin
          fields = {
            id:          result.read(Int64),
            hostname:    result.read(String),
            dir:         result.read(String),
            name:        result.read(String),
            dev:         result.read(Int32),
            inode:       result.read(Int32),
            size:        result.read(Int64),
            permissions: File::Permissions.new(result.read(Int32).to_i16),
            filetype:    File::Type.parse(result.read(String)),
            flags:       File::Flags.parse(result.read(String)),
            mtime:       Time.unix(result.read(Int64)),
            uid:         result.read(Int32),
            owner:       result.read(String),
            gid:         result.read(Int32),
            group:       result.read(String),
            created_at:  Time.unix(result.read(Int64)),
            updated_at:  Time.unix(result.read(Int64)),
            crc32:       result.read(String?),
            sha256:      result.read(String?),
            link_target: result.read(String?),
          }
        end
        debug "from_resultset() - #{fields.inspect}"
        self.new(**fields)
      end

      def self.find(db : DB::Database, where : String? = nil, *args)
        debug "find(#{where}, #{args}) do ... end"
        sql_command = String.build do |str|
          str << "SELECT \"id\", #{@@properties.map { |p| "\"#{p}\"" }.join(", ")} FROM entry"
          unless where.nil?
            str << " WHERE #{where}"
          end
          str << " ORDER BY hostname, dir, name;"
        end
        debug "SQL: %s", sql_command
        db.query(sql_command, *args) do |rs|
          rs.each do
            yield self.from_resultset(rs).as(self)
          end
        end
      end

      def self.find(db : DB::Database, where : String? = nil, *args)
        debug "find(#{where}, #{args})"
        sql_command = String.build do |str|
          str << "SELECT \"id\", #{@@properties.map { |p| "\"#{p}\"" }.join(", ")} FROM entry"
          unless where.nil?
            str << " WHERE #{where}"
          end
          str << " ORDER BY hostname, dir, name;"
        end
        debug "SQL %s", sql_command
        list = [] of self
        db.query(sql_command, *args) do |rs|
          rs.each do
            list.push self.from_resultset(rs).as(self)
          end
        end
        list
      end

      def self.find_one(db : DB::Database, where : String, *args)
        debug "find_one(#{where.inspect}, #{args})"
        result = self.find(db, where, *args)
        result.first
      end

      def self.by_id(id : Int, db : DB::Database)
        debug "by_id(#{id.inspect})"
        self.find_one(db, "id=?", id)
      end

      def self.by_path(db : DB::Database, path : Path | String, hostname : String = @@hostname)
        debug "by_path(#{path.inspect}, #{hostname.inspect})"
        dirname = File.dirname path.to_s
        basename = File.basename path.to_s
        self.find_one(db, "hostname=? AND dir=? AND name=?", hostname, dirname, basename)
      end

      def is_dir?
        File.directory?(self.path)
      end

      def to_json(io : IO)
        JSON.build(io) do |json|
          json.object do
            json.field "id", @id
            json.field "hostname", @hostname
            json.field "dir", @dir
            json.field "name", @name
            json.field "dev", @dev
            json.field "inode", @inode
            json.field "size", @size
            json.field "permissions", @permissions.value
            json.field "filetype", @filetype.to_s
            json.field "flags", @flags.to_s
            json.field "uid", @uid
            json.field "owner", @owner
            json.field "gid", @gid
            json.field "group", @group
            json.field "sha256", @sha256
            json.field "crc32", @crc32
            json.field "link_target", @link_target unless @link_target.nil?
            if @created_at.nil?
              json.field "created_at", nil
              json.field "created_at_seconds", nil
            elsif @created_at.class == Time
              json.field "created_at", @created_at.as(Time).to_s("%Y-%m-%dT%H:%M:%S")
              json.field "created_at_seconds", @created_at.as(Time).to_unix
            end
            if @updated_at.nil?
              json.field "updated_at", nil
              json.field "updated_at_seconds", nil
            elsif @updated_at.class == Time
              json.field "updated_at", @updated_at.as(Time).to_s("%Y-%m-%dT%H:%M:%S")
              json.field "updated_at_seconds", @updated_at.as(Time).to_unix
            end
          end
        end
      end

      def calculate_checksums(force = false)
        if !self.filetype.nil? && self.filetype.as(File::Type).file?
          info "calculate_checksums(force: #{force}) crc32=#{@crc32} sha256=#{@sha256} for #{self.path}"
          if @sha256.nil? || @crc32.nil? || force
            buffer_size = 4096
            buffer = Bytes.new(buffer_size)
            # crc32 = CRC32.initial
            crc32 = 0_u32
            size = self.size.as(Int64)
            path = self.path
            File.open(path) do |input|
              io = OpenSSL::DigestIO.new(input, "SHA256")
              bytes = 0
              loop do
                bytes = io.read(buffer)
                break if bytes == 0
                crc32 = CRC32.update(buffer[0, bytes], crc32)
                bytes += buffer_size
                if size > 128 * 1024 && 0 == bytes % (64 * buffer_size)
                  STDERR.printf "\r%6.2f%% %s", 100.0 * bytes / size, path
                end
              end
              @sha256 = io.digest.hexstring
              STDERR.printf "\r\e[K"
            end
            @crc32 = "%08x" % crc32
            info "crc32=#{@crc32} sha256=#{@sha256}"
          end
        end
      end

      def sha256
        if @sha256.nil?
          self.calculate_checksums
          @sha256
        end
      end

      def crc32
        if @crc32.nil?
          self.calculate_checksums
        end
        @crc32
      end

      def to_json
        String.build do |str|
          to_json str
        end
      end
    end
  end
end
