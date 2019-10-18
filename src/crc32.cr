require "crc32"
# require "lib_z"

cksum = 0_u32
# cklz=0_u32
file = ARGV.shift

File.open(file) do |input|
  bytes = 0
  buffer = Bytes.new(4096)
  loop do
    bytes = input.read(buffer)
    puts "#{buffer.class}\t#{bytes}"
    break if 0 == bytes
    cksum = CRC32.update buffer[0, bytes], cksum
  end
end

printf "0x%08x\n", cksum
