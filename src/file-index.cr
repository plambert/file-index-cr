# require "phreak"
require "./file/**"

class CLI
  File::Index::Logger.import
  alias ArgsType = Array(String)
  alias ParameterCallback = Proc(String, ParameterDefinition, Array(String), Bool?)
  alias ParameterDefinition = NamedTuple(
    short: Array(Char),
    long: Array(String),
    desc: String?,
    bool: Bool,
    opt: Bool,
    key: String,
    callback: ParameterCallback,
  )
  class_property logger : File::Index::Logger = File::Index::Logger.instance
  class_property parameters : Array(ParameterDefinition) = [] of ParameterDefinition

  property dbfile : String
  property params : Array(String) = [] of String
  property force_checksum : Bool = false

  private def self.param(**opts)
    desc : String = case opts[:desc]?
    when String
      opts[:desc].as(String)
    when Array(String)
      opts[:desc].as(Array(String)).join("\n")
    when Nil
      nil
    else
      raise "#{opts[:desc]?.inspect}: unknown description value"
    end

    long : Array(String) = case opts[:long]?
    when String
      opts[:long].as(String).split(/\s+/)
    when Array(String)
      opts[:long].as(Array(String))
    when Nil
      [] of String
    else
      raise "#{opts[:long]?.inspect}: unknown long value"
    end

    short : Array(Char) = case opts[:short]?
    when Char
      [opts[:short].as(Char)]
    when String
      opts[:short].as(String).chars
    when Nil
      [] of Char
    else
      raise "#{opts[:short]?.inspect}: unknown short value"
    end

    bool : Bool = case opts[:bool]?
    when Bool
      opts[:bool].as(Bool)
    when Nil
      false
    else
      raise "#{opts[:bool]?.inspect}: unknown bool value"
    end

    opt : Bool = case opts[:opt]?
    when Bool
      opts[:opt].as(Bool)
    when Nil
      false
    else
      raise "#{opts[:opt]?.inspect}: unknown opt value"
    end

    callback : ParameterCallback = case opts[:callback]?
    when ParameterCallback
      opts[:callback].as(ParameterCallback)
    when Nil
      ->default_param(ParameterDefinition, ArgsType)
    else
      raise "#{opts[:callback]?.inspect}: unknown callback value"
    end

    key : String = case opts[:key]?
    when String
      opts[:key].as(String)
    when Nil
      if long.size > 0
        long[0]
      elsif short.size > 0
        "opt_#{short[0]}"
      else
        "opt_#{@@anon_opt_idx}"
        @@anon_opt_idx += 1
      end
    else
      raise "#{opts[:key]?.inspect}: unknown key value"
    end

    {long: long, short: short, desc: desc, bool: bool, opt: opt, callback: callback, key: key}
  end

  def self.default_param(named : String, pdef : ParameterDefinition, args : Array(String)) : Bool?
    if pdef[:opt]
      @opts[pdef[:key]] = args.shift
    elsif pdef[:bool]
      @opts[pdef[:key]] = named[0, 3] == "no-" ? false : true
    else
      @opts[pdef[:key]]
    end
  end

  def initialize
    @dbfile = Path[ENV["HOME"] + "/.cache/file-index-cr.sqlite3"].expand.to_s
    @dbfile = Path[ENV["FILE_INDEX_DBFILE"]].expand.to_s if ENV["FILE_INDEX_DBFILE"]?
    @@parameters = [
      {
        long:     "help",
        short:    "h",
        desc:     "Show this help",
        callback: ->(args : Array(String)) { self.help; args },
      },
      {
        long:     "verbose",
        short:    "v",
        desc:     "Enable debug logging",
        callback: ->{ loglevel File::Index::Logger::LogLevel::DEBUG },
      },
      {
        long:     "quiet",
        short:    "q",
        desc:     "Only log warnings and errors",
        callback: ->{ loglevel File::Index::Logger::LogLevel::WARN },
      },
      {
        long:     "default-logging",
        desc:     "Default log level, INFO and above",
        callback: ->{ loglevel File::Index::Logger::LogLevel::INFO },
      },
      {
        long:     %w{checksum always-checksum force-checksum},
        short:    "c",
        desc:     "Always checksum files, even if there are already checksums",
        bool:     true,
        callback: ->(bool : Bool) { @force_checksum = bool },
      },
      {
        long:     %w{dbfile file db},
        short:    "f",
        desc:     "Path to the database file",
        opt:      true,
        callback: ->(filepath : String) { @dbfile = Path[filepath].expand.to_s },
      },
    ]
    self.run
  end

  def find_param(short : String | Char)
    @@parameters.each do |param|
      return param if param[:short]? && param[:short].to_s
    end
  end

  def run
    args = ARGV.dup
    shorts : String = ""
    parameter_for_short = {} of Char => ParameterDefinition
    parameter_for_long = {} of String => ParameterDefinition

    @@parameters.each do |param|
      long : Array(String)
      short = param[:short]
      if short.is_a?(Char)
        parameter_for_short[short] = param
      elsif short.is_a?(String)
        short = short.as(String)
        if short.size == 0
          raise "cannot use empty string for short in parameter definition: #{param.inspect}"
        elsif short =~ /(.).*\1/
          raise "cannot have the same character twice within short value of a parameter definition: #{$1}"
        else
          short.each_char do |c|
            if parameter_for_short[c]
              raise "two parameters cannot use the same short character: #{parameter_for_short[c].inspect} vs. #{param.inspect}"
            else
              parameter_for_short[c] = param
            end
          end
        end
      end
      if param[:long].is_a?(String)
        long = param[:long].strip.split(/\s+/)
      elsif param[:long].is_a?(Array(String))
        long = param[:long]
      else
        long = [] of String
      end
      long.each do |l|
        l = l.downcase
        l.sub!(/^-+/, "")
        l.gsub!(/_/, "-")
        parameter_for_long[l] = param
        if l =~ /-/
          parameter_for_long[l.gsub(/-/, "_")] = param
        end
      end
    end

    puts "parameters: #{@@parameters.inspect}"
    puts "short: #{parameter_for_short.inspect}"
    puts "long: #{parameter_for_long.inspect}"
    # while args.size > 0
    #   opt = args.shift
    #   case opt
    #   when /\A-[^-]+\z/
    #     opt[1..-1].each_char do |c|
    #     end
    #   end
    #   # if (opt =~ )

    #   # end
    # end
    # Phreak.parse! do |root|
    #   root.bind short_flag: 'h', long_flag: "help", description: "Show this help" do
    #     puts root
    #   end

    #   root.bind short_flag: 'f', long_flag: "dbfile", description: "The database file to use" do
    #     @dbfile = root.next_token
    #   end

    #   root.bind short_flag: 'c', long_flag: "checksum", description: "Always checksum files" do
    #     @checksum = true
    #   end

    #   root.bind long_flag: "no-checksum", description: "Do not checksum files" do
    #     @checksum = false
    #   end

    #   root.bind short_flag: 'v', long_flag: "verbose", description: "Enable debug output" do
    #     loglevel File::Index::Logger::LogLevel::DEBUG
    #   end

    #   root.bind short_flag: 'q', long_flag: "quiet", description: "Disable debug output" do
    #     loglevel File::Index::Logger::LogLevel::WARN
    #   end

    #   root.bind word: "add", description: "Index the given files or directories" do |sub|
    #     sub.grab do |sub, name|
    #       params << name
    #     end
    #   end
    # end
    # puts "DBFILE = #{@dbfile.inspect}"
    # puts "PARAMS = #{@params.inspect}"
  end

  # class CLI < Admiral::Command
  #   @@logger : File::Index::Logger = File::Index::Logger.instance

  #   define_version "1.0.0"
  #   define_help description: "Manage SQLite database index of file metadata"
  #   define_flag dbfile : String,
  #     description: "The database file to use",
  #     default: Path[ENV["FILE_INDEX_DBFILE"]? || "~/.cache/file-index-cr.sqlite3"].expand.to_s,
  #     long: dbfile,
  #     short: f,
  #     required: true
  #   define_flag verbose : Bool,
  #     description: "Enable verbose output",
  #     default: false,
  #     long: verbose,
  #     short: v,
  #     required: true
  #   define_flag always_checksum : Bool,
  #     description: "Always recalculate checksums",
  #     default: true,
  #     long: checksum,
  #     short: c
  #   define_flag update_checksum : Bool,
  #     description: "Update file checksums for changed files that already have checksums",
  #     default: true,
  #     long: update,
  #     short: u

  #   class Add < Admiral::Command
  #     define_help description: "Add or update files/directories in the file-index database"

  #     def run
  #       dbfile = parent.flags.as(CLI::Flags).dbfile
  #       verbose = parent.flags.as(CLI::Flags).verbose
  #       checksum_mode = File::Index::ChecksumMode.for always_checksum: parent.flags.as(CLI::Flags).always_checksum, update_checksum: parent.flags.as(CLI::Flags).update_checksum
  #       loglevel verbose ? File::Index::Logger::LogLevel::DEBUG : File::Index::Logger::LogLevel::INFO
  #       start_time = Time.local
  #       unless File.file? dbfile
  #         error "%s: file-index database does not exist, use \`%s create\` to create it" % [dbfile, PROGRAM_NAME]
  #         exit 1
  #       end
  #       index = File::Index.new dbfile: dbfile

  #       if arguments.size > 0
  #         arguments.each { |a| index.add a, checksum_mode: checksum_mode, start_time: start_time }
  #       else
  #         index.add ".", checksum_mode: checksum_mode
  #       end

  #       info "indexing complete"

  #       index.all.each do |entry|
  #         puts entry.to_json
  #       end
  #     end
  #   end

  #   register_sub_command add, Add

  #   class Create < Admiral::Command
  #     define_help description: "Create an empty file-index database file"

  #     def run
  #       dbfile = parent.flags.as(CLI::Flags).dbfile
  #       if File.exists?(dbfile)
  #         fail 13, "%s: cannot create file, it already exists", dbfile
  #       else
  #         File::Index.create_db dbfile: dbfile
  #         info "%s: empty index file created", dbfile
  #       end
  #     end
  #   end

  #   register_sub_command create, Create

  #   class Reset < Admiral::Command
  #     define_help description: "Reset the file-index database (deletes all entries!)"

  #     def run
  #       dbfile = parent.flags.as(CLI::Flags).dbfile
  #       if File.file?(dbfile)
  #         File::Index.reset! dbfile: dbfile
  #         info "%s: database reset", dbfile
  #       else
  #         error "%s: database file not found", dbfile
  #       end
  #     end
  #   end

  #   register_sub_command reset, Reset

  #   class Schema < Admiral::Command
  #     define_help description: "Output the SQL schema for the database (for development/debugging)"

  #     def run
  #       File::Index::SQL.schema.each { |stmt| puts stmt }
  #     end
  #   end

  #   register_sub_command schema, Schema

  #   class Checksum < Admiral::Command
  #     define_help description: "Calculate checksums for the given files"

  #     def run
  #       dbfile = parent.flags.as(CLI::Flags).dbfile
  #       verbose = parent.flags.as(CLI::Flags).verbose
  #       checksum_mode = File::Index::ChecksumMode.for always_checksum: parent.flags.as(CLI::Flags).always_checksum, update_checksum: parent.flags.as(CLI::Flags).update_checksum
  #       loglevel verbose ? File::Index::Logger::LogLevel::DEBUG : File::Index::Logger::LogLevel::INFO
  #       unless File.file? dbfile
  #         error "%s: file-index database does not exist, use \`%s create\` to create it" % [dbfile, PROGRAM_NAME]
  #         exit 1
  #       end
  #       index = File::Index.new dbfile: dbfile

  #       if arguments.size > 0
  #         arguments.each do |a|
  #           index.add a, checksum_mode: checksum_mode
  #         end
  #       else
  #         index.add ".", checksum_mode: checksum_mode
  #       end

  #       info "indexing complete"

  #       index.all.each do |entry|
  #         puts entry.to_json
  #       end
  #     end
  #   end

  #   register_sub_command checksum, Checksum

  #   class Search < Admiral::Command
  #     define_help description: "Search the file-index database (NOT IMPLEMENTED)"

  #     def run
  #       raise "Not implemented"
  #     end
  #   end

  #   class Update < Admiral::Command
  #     define_help description: "Update the file-index database (NOT IMPLEMENTED)"

  #     def run
  #       raise "Not implemented"
  #     end
  #   end

  #   def run
  #     puts help
  #   end
  # end
  def help
    raise "unimplemented"
  end
end

CLI.new
