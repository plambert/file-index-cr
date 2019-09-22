queue = [] of String

if ARGV.size > 0
  ARGV.each { |a| queue.push a }
else
  queue.push(".")
end

while queue.size > 0
  item = queue.shift
  info = File.info(item)
  printf "%4d %08b %s%s\n", info.type.value, info.flags.value, item, info.directory? ? "/" : ""
  if info.directory?
    Dir.new(item).children.each do |child|
      queue.push(File.join(item, child))
    end
  end
end
