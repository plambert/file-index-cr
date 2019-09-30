class File
  class Index
    class Exception < Exception
      class WrongHost < File::Index::Exception
        def initialize(wrong : String | File::Entry, local : String = System.hostname)
          remote = typeof(wrong) == "File::Entry" ? wrong.hostname : wrong
          super(message: "Attempt to perform file operation on entry from '%s' on host '%s'" % [remote, local])
        end
      end
    end
  end
end
