module Paradoxical::FileParser
  def corrections
    @corrections ||= {}
  end

  def add_correction path, &block
    corrections[ path ] ||= []

    corrections[ path ] << block
  end

  def exists? relative_path
    File.exist? full_path_for relative_path
  end

  def glob relative_path
    Dir[ full_path_for relative_path ].map do |path| path.reverse.chomp( (root.to_s + '/').reverse ).reverse end
  end

  # When the caller doesn't specify an `encoding:`, read as UTF-8
  # (the default for every modern PDS title) and fall back to
  # Windows-1252 if the bytes aren't valid UTF-8. Among PDS titles
  # only EU4 (predominantly Windows-1252) and HOI4 (one stray file
  # `online_accountcreate.gui` with `§` Windows-1252 markup bytes)
  # rely on this fallback, but mod authors on Windows often save
  # scripts as Windows-1252 unintentionally, so we cover those files
  # for free.
  #
  # Mod scripts that pass an explicit `encoding:` get exactly that
  # encoding with no fallback.
  #
  # Raises EncodingError if the final encoding is not valid.
  def read relative_path, encoding: nil
    full_path = full_path_for(relative_path)
    data = File.read full_path, encoding: (encoding || Encoding::UTF_8)
    enforce_encoding! data, encoding: encoding, path: full_path
  end

  def full_path_for path
    path.to_s.start_with?('/') ? path : root.join( path )
  end

  def parse_file path, mutex: nil, ignore_cache: false, encoding: nil
    document = nil

    mutex ||= Object.new.tap do |o| o.define_singleton_method :synchronize do |&block| block.call end end

    mutex.synchronize do
      document = @file_cache[path]
    end

    return document unless ignore_cache or document.nil?

    data = read path, encoding: encoding

    encoding ||= data.encoding

    bom = false
    
    if encoding == Encoding::UTF_8 then 
      bom_marker = "\xEF\xBB\xBF"
      bom = data.start_with? bom_marker
      # Strip BOMs anywhere in the file. Imperator ships at least two
      # files (concatenation artifacts) with a second BOM mid-content;
      # only the leading one carries author intent, the rest are garbage.
      data.gsub!(bom_marker, "")
    end

    ( corrections[ path ] or [] ).each do |block|
      block.call data
    end

    document = parse data, path: path, bom: bom, encoding: encoding

    mutex.synchronize do
      @file_cache[path] = document
    end

    return document
  end

  def parse data, path: nil, bom: false, encoding: nil
    document = Paradoxical::Parser.parse data

    document.instance_variable_set( :@owner, self )
    document.instance_variable_set( :@path, path )
    document.instance_variable_set( :@line_break, data.include?("\r") ? "\r\n" : "\n")
    document.instance_variable_set( :@bom, bom )
    document.instance_variable_set( :@encoding, encoding )

    document
  rescue Paradoxical::Parser::ParseError => error
    prefix = path ? "#{path}#{ self.is_a?(Paradoxical::Mod) ? " (#{name})" : '' }: " : ""
    raise Paradoxical::Parser::ParseError, "#{prefix}#{error.message}"
  end

  protected

  def enforce_encoding! data, encoding: nil, path: nil
    return data if data.valid_encoding?

    raise EncodingError, "Encoding for file: #{path} did not match passed value: #{encoding}" unless encoding.nil?

    data.force_encoding Encoding::WINDOWS_1252
    raise EncodingError, "Unknown encoding for file: #{path}" unless data.valid_encoding?
    data
  end


end