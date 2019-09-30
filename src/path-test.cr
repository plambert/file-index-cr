require "./file/path"

default_tests = [
  ".",
  "././LICENSE",
  "TEMPFILE()",
  "TEMPFILE_OPEN()",
]

def show(original_string)
  printf "\e[32m%-6s\e[0m %10s: %s\n", "[OK]", "new", original_string
  path = FilePath.new(original_string)
  saved_string = path.to_s
  printf "\e[32m%-6s\e[0m %10s: %s\n", "[OK]", ".to_s", saved_string
  printf "\e[32m%-6s\e[0m %10s: %s\n", "[OK]", ".canonical", path.canonical
  printf "\e[32m%-6s\e[0m %10s: %s\n", "[OK]", ".absolute", path.absolute
  printf "\e[32m%-6s\e[0m %10s: %s\n", "[OK]", ".realpath", path.realpath
  throwaway = path.canonical
  throwaway = path.absolute
  throwaway = path.realpath
  if original_string == saved_string
    printf "\e[32m%-6s\e[0m creating path did not change path string\n", "[OK]"
  else
    printf "\e[31m%-6s\e[0m creating path changed path string from '%s' to '%s'!\n", "[FAIL]", original_string, saved_string
  end
  if saved_string == path.to_s
    printf "\e[32m%-6s\e[0m path string has not changed\n", "[OK]"
  else
    printf "\e[31m%-6s\e[0m path string has changed from '%s' to '%s'!\n", "[FAIL]", saved_string, path.to_s
  end
  printf "\n"
end

tests = ARGV.size > 0 ? ARGV : default_tests
tests.each do |arg|
  if arg == "TEMPFILE()"
    tempfile = FilePath.tempfile
    # tempfile = FilePath.tempfile
    printf "\e[32m%-6s\e[0m %10s: %s\n\n", "[OK]", "tempfile", tempfile
  elsif arg == "TEMPFILE_OPEN()"
    tempfile = FilePath.tempfile_open
    printf "\e[32m%-6s\e[0m %10s: fd=%d %s\n\n", "[OK]", "tempfile_open", tempfile.fd, tempfile.path
    File.delete(tempfile)
  else
    show arg
  end
end
