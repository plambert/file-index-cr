require "db"

class File
  class Index
    class SQL
      @@schema : String = {{read_file("src/file/index/schema.sql")}}

      def self.quote_string(val)
        "'%s'" % [val.to_s.gsub(/'/, "''")]
      end

      def self.quote_identifier(val)
        "\"%s\"" % [val.to_s.gsub(/"/, "\"\"")]
      end

      def self.quote_array(val)
        "(%s)" % [val.to_a.map { |e| self.quote_string e }.join ", "]
      end

      def self.schema
        @@schema.split(%r{(?<=;)[ \t]*\r?\n\s*}).select { |stmt| stmt =~ /\S/ }
      end

      def self.apply(db : DB::Database)
        self.schema.each do |statement|
          result = db.exec statement
        end
      end
    end
  end
end
