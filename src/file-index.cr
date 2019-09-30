require "admiral"
require "./file/**"

class CLI < Admiral::Command
  define_version "1.0.0"
  define_help description: "Manage SQLite database index of file metadata"
  define_flag dbfile : String,
    description: "The database file to use",
    default: Path["~/.cache/file-index-cr.sqlite3"].expand.to_s,
    long: dbfile,
    short: f,
    required: true
  define_flag verbose : Bool,
    description: "Enable verbose output",
    default: false,
    long: verbose,
    short: v,
    required: true

  class Add < Admiral::Command
    define_help description: "Add or update files/directories in the file-index database"

    def run
      dbfile = parent.flags.as(CLI::Flags).dbfile
      unless File.file? dbfile
        STDERR.puts "\e[31;1m#{dbfile}: file-index database does not exist\e[0m"
        STDERR.puts
        STDERR.puts "Create it with:"
        STDERR.puts "  #{PROGRAM_NAME} create --dbfile=#{dbfile}"
        exit 1
      end
      index = File::Index.new dbfile: dbfile

      if arguments.size > 0
        arguments.each { |a| index.add(a) }
      else
        index.add(".")
      end

      print "\e[34;1mCOMPLETED INDEXING\e[0m\n\n"

      index.all.each do |entry|
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
        STDERR.puts "#{dbfile}: cannot create, file exists"
      else
        File::Index.create_db dbfile: dbfile
        STDOUT.puts "#{dbfile}: empty index file created"
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
      end
    end
  end

  register_sub_command reset, Reset

  class Search < Admiral::Command
    define_help description: "Search the file-index database (NOT IMPLEMENTED)"

    def run
      raise "Not implemented"
    end
  end

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
