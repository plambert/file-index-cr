struct Info::File
  def inode
    @stat.ino
  end

  def dev
    @stat.dev
  end
end
