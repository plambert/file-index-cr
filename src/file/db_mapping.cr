class File::Mapping::Permissions
  def from_rs(rs : DB::ResultSet)
    File::Permissions.new(rs.read(UInt64))
  end
end

class File::Mapping::Type
  def from_rs(rs : DB::ResultSet)
    File::Type.new(rs.read(UInt32))
  end
end

class File::Mapping::Flags
  def from_rs(rs : DB::ResultSet)
    File::Flags.new(rs.read(UInt32))
  end
end
