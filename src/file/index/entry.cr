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
      class_property hostname : String = System.hostname
      alias AnyValue = Nil | Int64 | String | Int32 | File::Permissions | File::Type | File::Flags | Time
      alias FullRecord = NamedTuple(
        id: Int64?,
        hostname: String,
        dir: String,
        name: String,
        dev: Int32,
        inode: Int32,
        size: Int64,
        permissions: File::Permissions,
        filetype: File::Type,
        flags: File::Flags,
        mtime: Time,
        uid: Int32,
        owner: String,
        gid: Int32,
        group: String,
        created_at: Time,
        updated_at: Time,
        crc32: String?,
        sha256: String?,
        link_target: String?,
      )
      @@properties_required : Array(String) = %w{hostname dir name dev inode size permissions filetype flags mtime uid owner gid group created_at updated_at}
      @@properties : Array(String) = @@properties_required + %w{crc32 sha256 link_target}
      @@properties_all : Array(String) = %w{id} + @@properties
      property id : Int64?
      property hostname : String
      property dir : String
      property name : String
      property dev : Int32
      property inode : Int32
      property size : Int64
      property permissions : File::Permissions
      property filetype : File::Type
      property flags : File::Flags
      property mtime : Time
      property uid : Int32
      property owner : String
      property gid : Int32
      property group : String
      property created_at : Time
      property updated_at : Time
      @crc32 : String? = nil
      @sha256 : String? = nil
      property link_target : String?
      property info : File::Info?

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

      def local_info?(hostname : String = @@hostname)
        self.local_info
      rescue
        nil
      end

      def path
        Path.new(self.dir, self.name)
      end

      def update_from_filesystem(db : DB::Database, hostname : String = @@hostname)
        debug "update_from_filesystem() - #{self.inspect}"
        info = self.local_info hostname: hostname
        if self.is_modified?(info)
          @sha256 = nil
          @crc32 = nil
        end
        @dev = info.dev.to_i32
        @inode = info.inode
        @size = info.size.to_i64
        @permissions = info.permissions
        @filetype = info.type
        @flags = info.flags
        @mtime = info.modification_time
        @uid = info.owner
        @owner = System::User.find_by(id: info.owner.to_s).username
        @gid = info.group
        @group = System::Group.find_by(id: info.group.to_s).name
        @updated_at = Time.utc
        @created_at = self.updated_at if self.created_at.nil?
        @link_target = File.readlink(self.path.to_s) if info.symlink?
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
          begin
            result = db.exec(sql_command, @hostname, @dir, @name, @dev, @inode, @size, @permissions.value.to_i64,
              @filetype.to_s, @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @created_at.as(Time).to_unix, @updated_at.as(Time).to_unix, @crc32, @sha256, @link_target)
          rescue e : SQLite3::Exception
            fail 9, "INSERT failed:\n%s\n%d: %s\n" % [self.inspect, e.code, e.to_s]
          end
          @id = result.last_insert_id.as(Int64)
        else
          sql_command = "UPDATE entry SET dev=?, inode=?, size=?, permissions=?, filetype=?, flags=?, mtime=?, uid=?, owner=?, gid=?, \"group\"=?, updated_at=?, crc32=?, sha256=?, link_target=? WHERE id=?;"
          result = db.exec(sql_command, @dev, @inode, @size, @permissions.value.to_i64, @filetype.to_s,
            @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @updated_at.as(Time).to_unix, @crc32, @sha256, @link_target,
            @id)
        end
        self
      end

      def self.from_resultset(result)
        record = {} of String => Int64 | String | Int32 | File::Permissions | File::Type | File::Flags | Time | Nil
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

      def directory?
        if self.filetype
          self.filetype.directory?
        elsif self.hostname == @@hostname
          File.directory?(self.path)
        else
          false
        end
      end

      def file?
        if self.filetype
          self.filetype.file?
        elsif self.hostname == @@hostname
          File.file?(self.path)
        else
          false
        end
      end

      def to_json
        String.build do |str|
          to_json str
        end
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

      def is_modified?
        self.is_modified?(self.local_info)
      rescue
        nil
      end

      def is_modified?(info : File::Info)
        debug "is_modified?(info: %s)", info.inspect
        if info.modification_time != @mtime || info.size != @size
          true
        else
          false
        end
      end

      def is_modified?(info : Nil)
        nil
      end

      def can_checksum?(info : File::Info, hostname : String = @@hostname)
        reason = ""
        if !self.filetype
          reason = "filetype must be defined"
        elsif !self.filetype.is_a?(File::Type)
          reason = "filetype must be a File::Type"
        else
          filetype = self.filetype.as(File::Type)
          if !filetype.file?
            reason = "filetype is '#{filetype.to_s}': can only checksum a file"
          end
        end
        debug "%s: %s", self.path.to_s, reason if !reason.empty?
        {reason.empty?, reason}
      end

      def can_checksum?(hostname : String = @@hostname)
        self.can_checksum?(info: self.local_info, hostname: hostname)
      end

      def calculate_checksums(checksum_mode : ChecksumMode, start_time = Time.local)
        checksum_ok, reason = self.can_checksum?
        if !self.filetype || !self.filetype.is_a?(File::Type)
          raise "cannot checksum an entry without a filetype"
        elsif !self.filetype.as(File::Type).file?
          debug "%s: filetype is '%s': can only checksum a file", self.path.to_s, self.filetype.as(File::Type).to_s
        elsif checksum_mode.never?
          debug "%s: skipping checksum in NEVER mode", self.path.to_s
        elsif checksum_mode.modified_only? && !self.is_modified?
          debug "%s: skipping checksum in MODIFIED_ONLY mode, file not modified", self.path.to_s
        else
          if checksum_mode.modified_only?
            debug "%s: calculating checksums in MODIFIED_ONLY mode, file was modified", self.path.to_s
          else
            debug "%s: calculating checksums in ALWAYS mode", self.path.to_s
          end
          debug "calculate_checksums(checksum_mode; #{checksum_mode}, start_time: #{start_time.inspect}) crc32=#{@crc32} sha256=#{@sha256} for #{self.path}"
          buffer_size = 32768
          buffer = Bytes.new(buffer_size)
          crc32 = 0_u32
          size = self.size.as(Int64)
          path = self.path
          last_time = Time.unix(0)
          File.open(path) do |input|
            io = OpenSSL::DigestIO.new(input, "SHA256")
            progress = 0_u64
            loop do
              bytes = io.read(buffer)
              break if bytes == 0
              crc32 = CRC32.update(buffer[0, bytes], crc32)
              progress += bytes
              now = Time.local
              if (size > 128 * 1024) && (now - last_time).abs.to_f >= 1.0
                elapsed = now - start_time
                if elapsed.days > 0
                  duration = sprintf "%dd %02d:%02d:%02d", elapsed.days, elapsed.hours, elapsed.minutes, elapsed.seconds
                else
                  duration = sprintf "%02d:%02d:%02d", elapsed.hours, elapsed.minutes, elapsed.seconds
                end
                STDERR.printf "\r%s %6.2f%% %s", duration, 100.0 * progress / size, path.to_s.size > 130 ? path.to_s[0, 137] + "..." : path
                STDERR.flush
                last_time = now
              end
            end
            @sha256 = io.digest.hexstring
            elapsed = Time.local - start_time
            if elapsed.days > 0
              duration = sprintf "%dd %02d:%02d:%02d", elapsed.days, elapsed.hours, elapsed.minutes, elapsed.seconds
            else
              duration = sprintf "%02d:%02d:%02d", elapsed.hours, elapsed.minutes, elapsed.seconds
            end
            STDERR.printf "\r%s %6.2f%% %s\n", duration, 100.0, path.to_s.size > 130 ? path.to_s[0, 137] + "..." : path
          end
          @crc32 = "%08x" % crc32
          debug "crc32=#{@crc32} sha256=#{@sha256}"
        end
      end

      def sha256
        raise "not a file" unless self.filetype && self.filetype.as(File::Type).file?
        raise "no checksum" unless @sha256
        @sha256
      end

      def sha256?
        @sha256
      end

      def sha256!(checksum_mode : File::Index::ChecksumMode = File::Index::ChecksumMode::ALWAYS, start_time : Time = Time.local)
        if !@sha256
          self.calculate_checksums(checksum_mode: checksum_mode, start_time: start_time)
        end
        @sha256
      end

      def crc32
        raise "not a file" unless self.filetype && self.filetype.as(File::Type).file?
        raise "no checksum" unless @crc32
        @crc32
      end

      def crc32?
        @crc32
      end

      def crc32!(checksum_mode : File::Index::ChecksumMode = File::Index::ChecksumMode::ALWAYS, start_time : Time = Time.local)
        if !@crc32
          self.calculate_checksums(checksum_mode: checksum_mode, start_time: start_time)
        end
        @crc32
      end

      def self.properties(which : Symbol = :without_id)
        case which
        when :without_id
          @@properties
        when :all
          @@properties_all
        when :required, :mandatory
          @@properties_required
        else
          raise "#{which.to_s}: unknown property set"
        end
      end
    end
  end
end
