class File
  class Index
    class Logger
      enum LogLevel
        ERROR
        WARN
        INFO
        DEBUG
        TRACE
      end
      @@logger = File::Index::Logger.new level: ENV["FILE_INDEX_DEBUG"]? ? LogLevel::DEBUG : LogLevel::INFO
      @@program_name = PROGRAM_NAME.sub(/.*\//, "").to_s.as(String)
      @@ansi_enabled = STDERR.tty? ? true : false
      @@ansi_for_level : Hash(LogLevel, String) = {
        LogLevel::ERROR => "\e[31;1m",
        LogLevel::WARN  => "\e[31;1m",
        LogLevel::INFO  => "\e[32;1m",
        LogLevel::DEBUG => "\e[37m",
        LogLevel::TRACE => "\e[37;1m",
      }

      @@io_for_level = {} of LogLevel => IO
      @@io_for_level[LogLevel::ERROR] = STDERR
      @@io_for_level[LogLevel::WARN] = STDERR
      @@io_for_level[LogLevel::INFO] = STDOUT
      @@io_for_level[LogLevel::DEBUG] = STDERR
      @@io_for_level[LogLevel::TRACE] = STDERR
      # STDERR.puts typeof(@@io_for_level)

      property level : LogLevel

      def initialize(@level : LogLevel = LogLevel::INFO)
      end

      def self.instance
        @@logger
      end

      def log(level : LogLevel, format : String, *args)
        if level <= @level
          ansi = @@ansi_enabled ? @@ansi_for_level[level] : ""
          clear = @@ansi_enabled ? "\e[0m" : ""
          io = @@io_for_level[level]
          io.printf "%s %s #{ansi}[%5s]#{clear} #{format}\n", Time.local.to_s, @@program_name, level.to_s, *args
        end
      end

      def level(level : LogLevel)
        @level = level
      end

      macro make_log_methods(hash)
        {% for name, level in hash %}
          def {{name.id}}(format : String, *args : String)
            File::Index::Logger.instance.log {{level}}, format, *args
          end
          def {{name.id}}(message : String)
            File::Index::Logger.instance.log {{level}}, "%s", message
          end
        {% end %}
        def fail(rc : Int = 1, format : String = "aborted!", *args : String)
          File::Index::Logger.instance.log File::Index::Logger::LogLevel::ERROR, format, *args
          exit rc
        end
        def fail(rc : Int = 1, message : String = "aborted!")
          File::Index::Logger.instance.log File::Index::Logger::LogLevel::ERROR, "%s", message
          exit rc
        end
        def loglevel(level : File::Index::Logger::LogLevel)
          File::Index::Logger.instance.level(level)
        end
      end

      macro import
        File::Index::Logger.make_log_methods({
          "trace": File::Index::Logger::LogLevel::TRACE,
          "debug": File::Index::Logger::LogLevel::DEBUG,
          "info":  File::Index::Logger::LogLevel::INFO,
          "warn":  File::Index::Logger::LogLevel::WARN,
          "error": File::Index::Logger::LogLevel::ERROR,
        })
      end
    end
  end
end
