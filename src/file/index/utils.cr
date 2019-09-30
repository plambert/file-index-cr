struct Crystal::System::FileInfo
  def inode
    @stat.st_ino
  end

  def dev
    @stat.st_dev
  end
end
