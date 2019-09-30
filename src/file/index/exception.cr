class File
  class Index
    class Exception < Exception
      class WrongHost < File::Index::Exception
        def initialize(wrong : String | File::Index::Entry, local : String = System.hostname)
          if wrong.is_a? File::Index::Entry
            remote = wrong.hostname
          else
            remote = wrong.to_s
          end
          super(message: "Attempt to perform file operation on entry from '%s' on host '%s'" % [remote, local])
        end
      end
    end
  end
end
