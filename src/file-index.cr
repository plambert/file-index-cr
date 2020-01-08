require "admiral"
require "./file/**"

File::Index::Logger.import

class CLI < Admiral::Command
  @@logger : File::Index::Logger = File::Index::Logger.instance

  define_version "1.0.0"
  define_help description: "Manage SQLite database index of file metadata"
  define_flag dbfile : String,
    description: "The database file to use",
    default: Path[ENV["FILE_INDEX_DBFILE"]? || "#{ENV["HOME"]}/.cache/file-index-cr.sqlite3"].expand.to_s,
    long: dbfile,
    short: f,
    required: true
  define_flag verbose : Bool,
    description: "Enable verbose output",
    default: false,
    long: verbose,
    short: v,
    required: true
  define_flag always_checksum : Bool,
    description: "Always recalculate checksums",
    default: false,
    long: checksum,
    short: c
  define_flag update_checksum : Bool,
    description: "Update file checksums for changed files that already have checksums",
    default: true,
    long: update,
    short: u

  class Add < Admiral::Command
    define_help description: "Add or update files/directories in the file-index database"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      verbose = parent.flags.as(CLI::Flags).verbose
      checksum_mode = File::Index::ChecksumMode.for always_checksum: parent.flags.as(CLI::Flags).always_checksum, update_checksum: parent.flags.as(CLI::Flags).update_checksum
      loglevel verbose ? File::Index::Logger::LogLevel::DEBUG : File::Index::Logger::LogLevel::INFO
      start_time = Time.local
      unless File.file? dbfile
        error "%s: file-index database does not exist, use \`%s create\` to create it" % [dbfile, PROGRAM_NAME]
        exit 1
      end
      index = File::Index.new dbfile: dbfile
      list = [] of File::Index::Entry

      if arguments.size > 0
        arguments.each { |a| list += index.add a, checksum_mode: checksum_mode, start_time: start_time }
      else
        list += index.add ".", checksum_mode: checksum_mode
      end

      info "added %d entries", list.size.to_s

      list.each do |entry|
        puts entry.to_json
      end
    end
  end

  register_sub_command add, Add

  class Create < Admiral::Command
    define_help description: "Create an empty file-index database file"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      if File.exists?(dbfile)
        fail 13, "%s: cannot create file, it already exists", dbfile
      else
        File::Index.create_db dbfile: dbfile
        info "%s: empty index file created", dbfile
      end
    end
  end

  register_sub_command create, Create

  class Reset < Admiral::Command
    define_help description: "Reset the file-index database (deletes all entries!)"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      if File.file?(dbfile)
        File::Index.reset! dbfile: dbfile
        info "%s: database reset", dbfile
      else
        error "%s: database file not found", dbfile
      end
    end
  end

  register_sub_command reset, Reset

  class Schema < Admiral::Command
    define_help description: "Output the SQL schema for the database (for development/debugging)"

    def run
      File::Index::SQL.schema.each { |stmt| puts stmt }
    end
  end

  register_sub_command schema, Schema

  class Checksum < Admiral::Command
    define_help description: "Calculate checksums for the given files"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      verbose = parent.flags.as(CLI::Flags).verbose
      checksum_mode = File::Index::ChecksumMode.for always_checksum: parent.flags.as(CLI::Flags).always_checksum, update_checksum: parent.flags.as(CLI::Flags).update_checksum
      loglevel verbose ? File::Index::Logger::LogLevel::DEBUG : File::Index::Logger::LogLevel::INFO
      unless File.file? dbfile
        error "%s: file-index database does not exist, use \`%s create\` to create it" % [dbfile, PROGRAM_NAME]
        exit 1
      end
      index = File::Index.new dbfile: dbfile
      list = [] of File::Index::Entry

      if arguments.size > 0
        arguments.each do |a|
          list += index.add a, checksum_mode: checksum_mode
        end
      else
        list += index.add ".", checksum_mode: checksum_mode
      end

      info "%d entries added", list.size.to_s

      list.each do |entry|
        puts entry.to_json
      end
    end
  end

  register_sub_command checksum, Checksum

  class Search < Admiral::Command
    define_help description: "Search the file-index database (NOT IMPLEMENTED)"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      verbose = parent.flags.as(CLI::Flags).verbose
      loglevel verbose ? File::Index::Logger::LogLevel::DEBUG : File::Index::Logger::LogLevel::INFO
      unless File.file? dbfile
        error "%s: file-index database does not exist, use \`%s create\` to create it" % [dbfile, PROGRAM_NAME]
        exit 1
      end
      index = File::Index.new dbfile: dbfile

      if arguments.size > 0
        arguments.each do |a|
          entry = index[a]?
          if entry
            puts entry.to_json
          else
            STDERR.puts "#{a}: not found in index"
          end
        end
      else
        raise "expected at least one file or directory argument"
      end
    end
  end

  register_sub_command search, Search

  class Update < Admiral::Command
    define_help description: "Update the file-index database (NOT IMPLEMENTED)"

    def run
      raise "Not implemented"
    end
  end

  def run
    puts help
  end
end

CLI.run
