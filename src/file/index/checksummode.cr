class File
  class Index
    enum ChecksumMode
      NEVER
      ALWAYS
      MODIFIED_ONLY

      def self.for(always_checksum : Bool, update_checksum : Bool)
        if always_checksum
          ALWAYS
        elsif update_checksum
          MODIFIED_ONLY
        else
          NEVER
        end
      end
    end
  end
end
