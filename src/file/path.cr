# a better Path class, more like perl5's Path::Tiny

lib LibC
  fun mktemp(x0 : Char*) : LibC::Int
end

class File < IO::FileDescriptor
  def initialize(@path : String, fd : LibC::Int)
    super(fd, blocking: true)
  end
end

class FilePath
  @@separator = "/"
  @@root = "/"
  property path : String

  def initialize(@path : String)
    raise "#{self.class} requires a non-zero length parameter" unless @path.size > 0
    @path = "/" if @path == "/.."
    self
  end

  def initialize(*paths)
    raise "#{self.class} requires a non-zero length parameter" unless paths.size > 0
    @path = ""
    paths.each do |entry|
      if @path.empty?
        @path = entry.to_s
      else
        self.append!(entry.to_s)
      end
    end
    self
  end

  def self.new(path : ::FilePath)
    path.clone
  end

  def self.[](path : String)
    self.new(path)
  end

  def self.[](path : ::FilePath)
    path.clone
  end

  def self.rootdir
    FilePath.new(@@root)
  end

  def self.cwd : FilePath
    self.new(Dir.current)
  end

  def self.tempfile(template : String? = nil, dir : String | FilePath = Dir.tempdir) : FilePath
    dir = dir.to_s.sub(/\/+$/, "")
    if template.nil?
      template = PROGRAM_NAME.gsub(%r{.*/}, "").gsub(%r{[^!-~]}, "_")
      path = "#{dir}/#{template}.XXXXXXXX"
    elsif template !~ %r{X{6,}}
      path = "" # so it can _never_ be null
      raise "expected tempfile template string with at least six XXXXXX placeholders, got: '#{template}'" unless template =~ %r{X{6,}}
    else
      path = "#{dir}/#{template}"
    end
    ptr = LibC.mktemp(path)
    raise Errno.new("mktemp(#{path.inspect}) failed") if ptr == 0
    FilePath.new(path)
  end

  def self.tempfile_open(template : String? = nil, dir : String | FilePath = Dir.tempdir) : File
    dir = dir.to_s.sub(/\/+$/, "")
    if template.nil?
      template = PROGRAM_NAME.gsub(%r{.*/}, "").gsub(%r{[^!-~]}, "_")
      path = "#{dir}/#{template}.XXXXXXXX"
    elsif template !~ %r{X{6,}}
      path = "" # so it can _never_ be null
      raise "expected tempfile template string with at least six XXXXXX placeholders, got: '#{template}'" unless template =~ %r{X{6,}}
    else
      path = "#{dir}/#{template}"
    end
    fd = LibC.mkstemp(path)
    raise Errno.new("mkstemp: '#{path.inspect_unquoted}'") if fd == -1
    File.new(path, fd)
  end

  def is_file?
    File.file?(@path)
  end

  def is_dir?
    File.directory?(@path)
  end

  def exists?
    File.exists?(@path)
  end

  def absolute?
    @path[0] == '/'
  end

  def append!(segment : String)
    segment = segment.rchop if segment.ends_with? '/'
    if segment[0] == '/'
      if @path == @@root || @path.size == 0
        @path = segment
      else
        raise "#{self.class} cannot join an absolute path to a non-root path"
      end
    else
      @path = @path + "/" + segment
    end
    self
  end

  def expand
    self.class.new(path: Path[@path].expand)
  end

  def expand!
    @path = Path[@path].expand
    self
  end

  def child(segment : String | self)
    if segment.to_s == "."
      self.clone
    else
      self.class.new(@path, segment.to_s)
    end
  end

  def children(pattern : Regex = /./)
    raise "FilePath[#{@path}] is not a directory" unless self.is_dir?
    children = [] of FilePath
    Dir[@path].each_child do |child|
      if child.match(pattern)
        children << self.child(child)
      end
    end
    children
  end

  def children(pattern : String = ".")
    self.children(Regex.new(pattern))
  end

  def files(pattern : Regex = /./)
    self.children(pattern).select! { |child| child.is_file? }
  end

  def files(pattern : String = ".")
    self.files(Regex.new(pattern))
  end

  def dirs(pattern : Regex = /./)
    self.children(pattern).select! { |child| child.is_dir? }
  end

  def dirs(pattern : String = /./)
    self.dirs(Regex.new(pattern))
  end

  def clone
    self.class.new(@path)
  end

  def clone(path : String)
    self.class.new(path)
  end

  def clone(path : self)
    path.clone
  end

  def parent : self
    if @path == "."
      self.class.new("..")
    elsif @path =~ %r{/}
      self.class.new(@path.sub(%r{/[^/]+$}, ""))
    elsif @path.ends_with?("/..")
      self.class.new(@path.chomp("/.."))
    elsif @path == self.class.rootdir.to_s
      raise "cannot find parent of rootdir: #{@path}"
    else
      raise "cannot find parent of path: #{@path}"
    end
  end

  def basename
    if @path == "/"
      ""
    else
      @path.sub(%r{.*/}, "")
    end
  end

  def dirname
    if @path == "/"
      "/"
    else
      @path.sub(%r{/[^/]+/?\z}, "")
    end
  end

  def to_s(io : IO)
    io << @path
  end

  def to_s : String
    @path.to_s
  end

  def absolute(relative : String | self = Dir.current)
    if self.absolute?
      self.clone
    else
      relative = FilePath.new(relative)
      if !relative.absolute?
        relative = relative.absolute
      end
      relative.child(self.to_s).absolute
    end
  end

  def canonical
    canonpath = @path
      .gsub(%r{/{2,}}, "/")            # xx////xx  -> xx/xx
      .gsub(%r{(?:/\.)+(?:/|\z)}, "/") # xx/././xx -> xx/xx
      .sub(%r{\A(?:\./)++(?=.)}, "")   # ./xx      -> xx
      .sub(%r{\A/(?:\.\./)+}, "/")     # /../../xx -> xx
      .sub(%r{\A/\.\.\z}, "/")         # /..       -> /
      .sub(%r{(?<=.)/\z}, "")          # xx/       -> xx
    self.class.new(canonpath)
  end

  def segments : Array(String)
    segs = @path.split(%r{/+})
    if segs[0].empty?
      segs[0] = "/"
    end
    segs
  end

  def realpath(relative : String | self = Dir.current)
    path = self.absolute(relative)
    if self.absolute?
      if File.directory?(self.to_s)
        quoted = @path.gsub(%r{(["\$\\])}, "\\\\\\1")
        real = %x{cd "#{quoted}" 2>/dev/null && pwd -P 2>/dev/null}.chomp
        raise "cannot get realpath of non-existent path: #{@path}" if real.empty?
        self.class.new(real)
      elsif File.directory?(self.parent.to_s)
        self.class.new(self.parent.realpath, self.basename)
      else
        raise "cannot get realpath of file in non-existent parent directory: #{self.parent}"
      end
    else
      relative = self.class.new(relative)
      relative = relative.absolute unless relative.absolute?
      self.class.new(relative, self.to_s).realpath
    end
  end
end
