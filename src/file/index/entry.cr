require "system/user"
require "system/group"
require "db"
require "sqlite3"
require "json"

class File::Entry
  @@properties = %w{hostname dir name dev inode size permissions filetype flags mtime uid owner gid group created_at updated_at}
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

  def self.new_from_filesystem(db : DB::Database, path : Path | String, hostname : String = @@hostname) : self
    STDERR.puts "new_from_filesystem(#{path.inspect})" if ENV["FILE_INDEX_DEBUG"]?
    path = File.real_path File.expand_path path.to_s
    new_entry : File::Entry
    begin
      new_entry = self.by_path(db, path, hostname)
      STDERR.puts "  found: #{new_entry.inspect}" if ENV["FILE_INDEX_DEBUG"]?
      raise "no new entry" unless new_entry
    rescue e
      STDERR.puts "  not found: creating new: #{e.inspect}" if ENV["FILE_INDEX_DEBUG"]?
      info = File.info(path.to_s, follow_symlinks = false)
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
        owner: System::User.find_by(id: info.owner.to_s).username,
        gid: info.group.to_i32,
        group: System::Group.find_by(id: info.group.to_s).name,
        updated_at: Time.utc,
        created_at: Time.utc,
      )
      STDERR.puts "  new: #{new_entry.inspect}" if ENV["FILE_INDEX_DEBUG"]?
    end
    new_entry.update(db)
    new_entry
  end

  def update_from_filesystem(db : DB::Database, hostname : String = @@hostname)
    STDERR.puts "update_from_filesystem() - #{self.inspect}" if ENV["FILE_INDEX_DEBUG"]?
    info = self.local_info hostname: hostname
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
    self.update(db)
  end

  def update(db : DB::Database)
    STDERR.puts "update() - #{self.inspect}" if ENV["FILE_INDEX_DEBUG"]?
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
        @filetype.to_s, @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @created_at.as(Time).to_unix, @updated_at.as(Time).to_unix)
      @id = result.last_insert_id.as(Int64)
    else
      sql_command = "UPDATE entry SET dev=?, inode=?, size=?, permissions=?, filetype=?, flags=?, mtime=?, uid=?, owner=?, gid=?, \"group\"=?, updated_at=? WHERE id=?;"
      result = db.exec(sql_command, @dev, @inode, @size, @permissions.value.to_i64, @filetype.to_s,
        @flags.to_s, @mtime.as(Time).to_unix, @uid, @owner, @gid, @group, @updated_at.as(Time).to_unix)
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
      }
    end
    STDERR.puts "from_resultset() - #{fields.inspect}" if ENV["FILE_INDEX_DEBUG"]?
    self.new(**fields)
  end

  def self.find(db : DB::Database, where : String? = nil, *args)
    STDERR.puts "find(#{where}, #{args}) do ... end" if ENV["FILE_INDEX_DEBUG"]?
    sql_command = String.build do |str|
      str << "SELECT \"id\", #{@@properties.map { |p| "\"#{p}\"" }.join(", ")} FROM entry"
      unless where.nil?
        str << " WHERE #{where}"
      end
      str << " ORDER BY hostname, dir, name;"
    end
    STDERR.printf "+ %s\n", sql_command if ENV["FILE_INDEX_DEBUG"]?
    db.query(sql_command, *args) do |rs|
      rs.each do
        yield self.from_resultset(rs).as(self)
      end
    end
  end

  def self.find(db : DB::Database, where : String? = nil, *args)
    STDERR.puts "find(#{where}, #{args})" if ENV["FILE_INDEX_DEBUG"]?
    sql_command = String.build do |str|
      str << "SELECT \"id\", #{@@properties.map { |p| "\"#{p}\"" }.join(", ")} FROM entry"
      unless where.nil?
        str << " WHERE #{where}"
      end
      str << " ORDER BY hostname, dir, name;"
    end
    STDERR.printf "+ %s\n", sql_command if ENV["FILE_INDEX_DEBUG"]?
    list = [] of self
    db.query(sql_command, *args) do |rs|
      rs.each do
        list.push self.from_resultset(rs).as(self)
      end
    end
    list
  end

  def self.find_one(db : DB::Database, where : String, *args)
    STDERR.puts "find_one(#{where.inspect}, #{args})" if ENV["FILE_INDEX_DEBUG"]?
    result = self.find(db, where, *args)
    result.first
  end

  def self.by_id(id : Int, db : DB::Database)
    STDERR.puts "by_id(#{id.inspect})" if ENV["FILE_INDEX_DEBUG"]?
    self.find_one(db, "id=?", id)
  end

  def self.by_path(db : DB::Database, path : Path | String, hostname : String = @@hostname)
    STDERR.puts "by_path(#{path.inspect}, #{hostname.inspect})" if ENV["FILE_INDEX_DEBUG"]?
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

  def to_json
    String.build do |str|
      to_json str
    end
  end
end
