require "db"
require "system/user"
require "system/group"

class File::Entry
  @@ordered_fields = %w{id dev inode perm type flags uid gid size mtime hostname path name}
  # property id : UInt64?
  DB.mapping({
    id:          {type: UInt64, nilable: true},
    path:        {type: String},
    name:        {type: String},
    dev:         {type: UInt32},
    inode:       {type: UInt64},
    size:        {type: UInt64},
    permissions: {type: File::Permissions, converter: File::Mapping::Permissions},
    filetype:    {type: File::Type, converter: File::Mapping::Type},
    flags:       {type: File::Flags, converter: File::Mapping::Flags},
    mtime:       {type: UInt32},
    uid:         {type: UInt32},
    gid:         {type: UInt32},
    owner:       {type: String},
    group:       {type: String},
    hostname:    {type: String},
  })

  def initialize(file : String, db : Database::DB, table : String = "entry")
    info = File.info(file)
    @path = File.dirname(file)
    @name = File.basename(file)
    @dev = info.dev
    @inode = info.inode
    @size = info.size
    @permissions = info.permissions
    @filetype = info.type
    @flags = info.flags
    @mtime = 0_i32
    {% if flag?(:darwin) %}
      @mtime = info.@stat.st_mtimespec
    {% else %}
      @mtime = info.@stat.st_mtim
    {% end %}
    @uid = info.owner
    @gid = info.group
    @owner = System::User.find_by id: @uid
    @group = System::Group.find_by id: @uid
    @id = nil
  end

  def self.new(id : UInt64, db : Database::DB, table : String = "entry")
    entries = self.from_rs(
      db.query("
          SELECT #{@@ordered_fields.join(", ")}
          FROM #{table}
          WHERE id = ?
          ORDER BY path, name
          LIMIT 1;
        ", id
      )
    )
    entries[0]
  end

  def modtime
    ::Time.new(@mtime, ::Time::Location::UTC)
  end

  def db_insert(db : Database::DB, table : String = "entry")
    db.exec("
        INSERT INTO #{table} (#{@@ordered_fields.join(", ")})
        VALUES (#{@@ordered_fields.map { "?" }.join(", ")});
      ",
      @id, @dev, @inode,
      @permissions.value, @filetype.value, @flags.value,
      @uid, @gid, @size,
      @mtime, @hostname, @path,
      @name
    )
  end

  def self.new(hostname : String, file : String | Path, db : Database::DB, table : String = "entry")
    if typeof(file) == "String"
      path = Path[file]
    else
      path = file
    end
    self.new(hostname, path.dirname, path.basename, db, table)
  end

  def self.new(hostname : String, dir : String, name : String, db : Database::DB, table : String = "entry")
    entries = self.from_rs(db.query("
        SELECT #{@@ordered_fields.join(", ")} FROM #{table}
        WHERE hostname = ? AND path = ? AND name = ?
        ORDER BY hostname, path, name
        LIMIT 1;
      ",
      hostname, path, name
    ))
    entries[0]
  end
end
