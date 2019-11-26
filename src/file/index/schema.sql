CREATE TABLE IF NOT EXISTS entry (
  "id"          INTEGER PRIMARY KEY,
  "hostname"    TEXT    NOT     NULL,
  "dir"         TEXT    NOT     NULL,
  "name"        TEXT    NOT     NULL,
  "dev"         INTEGER NOT     NULL,
  "inode"       INTEGER NOT     NULL,
  "size"        INTEGER NOT     NULL,
  "permissions" INTEGER NOT     NULL,
  "filetype"    TEXT    NOT     NULL,
  "flags"       TEXT    NOT     NULL,
  "mtime"       INTEGER NOT     NULL,
  "uid"         INTEGER NOT     NULL,
  "owner"       TEXT    NOT     NULL,
  "gid"         INTEGER NOT     NULL,
  "group"       TEXT    NOT     NULL,
  "created_at"  INTEGER NOT     NULL,
  "updated_at"  INTEGER NOT     NULL,
  "crc32"       TEXT    DEFAULT NULL,
  "sha256"      TEXT    DEFAULT NULL,
  "link_target" TEXT    DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS "idx_entry_uid"         ON entry ("uid");
CREATE INDEX IF NOT EXISTS "idx_entry_owner"       ON entry ("owner");
CREATE INDEX IF NOT EXISTS "idx_entry_gid"         ON entry ("gid");
CREATE INDEX IF NOT EXISTS "idx_entry_group"       ON entry ("group");
CREATE INDEX IF NOT EXISTS "idx_entry_size"        ON entry ("size");
CREATE INDEX IF NOT EXISTS "idx_entry_mtime"       ON entry ("mtime");
CREATE INDEX IF NOT EXISTS "idx_entry_hostname"    ON entry ("hostname");
CREATE INDEX IF NOT EXISTS "idx_entry_permissions" ON entry ("permissions");
CREATE INDEX IF NOT EXISTS "idx_entry_dir"         ON entry ("dir");
CREATE INDEX IF NOT EXISTS "idx_entry_name"        ON entry ("name");
CREATE INDEX IF NOT EXISTS "idx_entry_dir_name"    ON entry ("dir", "name");
CREATE INDEX IF NOT EXISTS "idx_entry_updated_at"  ON entry ("updated_at");
CREATE INDEX IF NOT EXISTS "idx_entry_crc32"       ON entry ("crc32");
CREATE INDEX IF NOT EXISTS "idx_entry_sha256"      ON entry ("sha256");
CREATE INDEX IF NOT EXISTS "idx_entry_inode"       ON entry ("inode");
CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_hostname_dir_name  ON entry ("hostname", "dir", "name");
