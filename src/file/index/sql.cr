require "db"

class File
  class Index
    class SQL
      @@schema : String = {{read_file("src/file/index/schema.sql")}}

      def self.schema
        @@schema.split(%r{(?<=;)[ \t]*\r?\n\s*}).select { |stmt| stmt =~ /\S/ }
      end

      def self.apply(db : Database::DB)
        self.schema.each do |statement|
          result = db.exec statement
        end
      end
    end
  end
end
