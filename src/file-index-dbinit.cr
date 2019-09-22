require "sqlite3"

DB.open "sqlite3://./file-index.sqlite3" do |db|
  db.exec "CREATE TABLE IF NOT EXISTS entry (
    id INTEGER PRIMARY KEY,
    dev INTEGER,
    inode INTEGER,
    perm INTEGER,
    type INTEGER,
    uid INTEGER,
    gid INTEGER,
    rdev INTEGER,
    size INTEGER,
    atime INTEGER,
    mtime INTEGER,
    ctime INTEGER,
    blksize INTEGER,
    blocks INTEGER,
    hostname TEXT,
    path TEXT,
    name TEXT
  );"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_uid              ON entry (uid);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_gid              ON entry (gid);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_size             ON entry (size);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_mtime            ON entry (mtime);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_hostname         ON entry (hostname);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_path             ON entry (path);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_name             ON entry (name);"
  db.exec "CREATE        INDEX IF NOT EXISTS idx_entry_path_name        ON entry (path, name);"
  db.exec "CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dev_ino ON entry (hostname, dev, ino);"
end
