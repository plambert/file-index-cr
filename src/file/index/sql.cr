require "db"

class File
  class Index
    class SQL
      @@schema : String = {{read_file("src/file/index/schema.sql")}}

      def schema
        @@schema.split(%r{;[ \t]*\r?\n}).map { |sql| "#{sql};" }
      end

      def apply(db : Database::DB)
        self.schema.each do |statement|
          result = db.exec statement
        end
      end
    end
  end
end
