# require "phreak"
# require "./file/**"

class CLI
  class Args
    alias ArgsType = Array(String)
    alias ParamDefType = NamedTuple(
      short: Array(Char),
      long: Array(String),
      desc: String?,
      bool: Bool,
      opt: Bool,
      key: String | Symbol,
      callback: ParameterCallback,
    )
    alias ParameterCallback = Proc(String, ParamDefType, Array(String), Bool?)
    alias Ints = Int8 | Int16 | Int32 | Int64 | Int128
    alias UInts = UInt8 | UInt16 | UInt32 | UInt64 | UInt128
    alias Floats = Float32 | Float64
    alias Number = Ints | UInts | Floats
    alias ParameterValue = String | Bool | Number | Nil

    class ParameterDefinition
      property long : Array(String)
      property short : Array(Char)
      property word : Array(String)
      property desc : String
      property is_bool : Bool
      property takes_arg : Bool
      property key : String | Symbol
      property callback : ParameterCallback

      def initialize(@desc,
                     @long = [] of String,
                     @short = [] of Char,
                     @word = [] of String,
                     @is_bool = false,
                     @takes_arg = false,
                     key : String | Symbol | Nil = nil,
                     @callback = ->CLI::Args.default_param(ParamDefType, ArgsType))
        raise "cannot set both 'bool' and 'takes_arg' in the same definition" if @is_bool && @takes_arg
        raise "must have at least one long, short, or word string set" if @long.size == 0 && @short.size == 0 && @word.size == 0
        raise "cannot have a long or short string, if there is a word string" if @word.size > 0 && (@long.size > 0 || @short.size > 0)
        if key
          @key = key.is_a?(String) ? key.as(String) : key.as(Symbol)
        elsif long[0]?
          @key = long[0]
        else
          raise "no key defined or guessable"
        end
      end

      def match(opt : String)
        @long.each do |long|
          return self if opt == "--#{long}"
          return self if opt == "--#{long.gsub(/-/, "_")}"
          return self if opt == "--#{long.gsub(/_/, "-")}"
          return nil
        end
        @short.each do |short|
          if opt == "-#{short}"
            return self
          else
            return nil
          end
        end
      end
    end

    class_property quickdef = %r{ \A \s*
        (?<names> (?: (?: -[a-z\#] | --[a-z][a-z0-9_\-]*) \s+ )+ )
        (?<desc> [a-z] .*?)?
        \s* \z
      }ix

    property defs : Array(ParamDefType) = [] of ParamDefType
    property opts : Hash(String, ParameterValue) = {} of String => ParameterValue

    def initialize(args : Array(String) = ARGV)
      yield self
      self
    end

    def param(quickdef : String)
      is_bool = false
      takes_arg = false
      desc = ""
      long = [] of String
      short = [] of Char
      key = ""
      callback = ->default_param(ParamDefType, ArgsType)
      if matchdata = quickdef.match(@@quickdef)
        case matchdata["type"]?
        when "bool", "boolean"
          bool = true
        when "value", "takes", "takes_arg",
             takes_arg = true
        end
        if matchdata["names"] && matchdata["names"] =~ /\S/
          matchdata["names"].strip.split(/\s+/).each do |name|
            key = name = name[2..-1] if name =~ /\A -- .* \* \z /x
            case name
            when "-\#"
              short << '#'
            when /^-([a-z])$/i
              short << $1
            when /^--([a-z][a-z0-9_\-]*)$/
              long << $1.downcase.gsub(/-/, "_")
            else
              raise "#{name}: cannot parse name from definition: #{quickdef.inspect}"
            end
          end
        end
        self.param(desc: desc, is_bool: is_bool, takes_arg: takes_arg, short: short, long: long, key: key)
      end
    end

    def param(**opts)
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
        ->default_param(ParamDefType, ArgsType)
      else
        raise "#{opts[:callback]?.inspect}: unknown callback value"
      end

      key : String | Symbol = case opts[:key]?
      when String
        opts[:key].as(String)
      when Symbol
        opts[:key].as(Symbol)
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

      @defs << ParameterDefinition.new(long: long, short: short, desc: desc, bool: bool, opt: opt, callback: callback, key: key)
    end

    def self.default_param(named : String, pdef : ParamDefType, args : Array(String)) : Bool?
      key = pdef[:key]
      if pdef[:opt]
        @opts[key] = args.shift
      elsif pdef[:bool]
        @opts[key] = named[0, 3] == "no-" ? false : true
      else
        @opts[key] = named
      end
    end

    def help
      raise "unimplemented"
    end
  end
end
