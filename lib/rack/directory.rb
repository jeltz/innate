require 'time'

module Rack
  # Rack::Directory serves entries below the +root+ given, according to the
  # path info of the Rack request. If a directory is found, the file's contents
  # will be presented in an html based index. If a file is found, the env will
  # be passed to the specified +app+.
  #
  # If +app+ is not specified, a Rack::File of the same +root+ will be used.

  class Directory
    DIR_FILE = "<tr><td class='name'><a href='%s'>%s</a></td><td class='size'>%s</td><td class='type'>%s</td><td class='mtime'>%s</td></tr>"
    DIR_PAGE = <<-PAGE
<html><head>
  <title>%s</title>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <style type='text/css'>
table { width:100%%; }
.name { text-align:left; }
.size, .mtime { text-align:right; }
  </style>
</head><body>
<h1>%s</h1>
<hr />
<table>
  <tr>
    <th class='name'>Name</th>
    <th class='size'>Size</th>
    <th class='type'>Type</th>
    <th class='mtime'>Last Modified</th>
  </tr>
%s
</table>
<hr />
</body></html>
    PAGE

    attr_reader :files
    attr_accessor :root, :path

    def initialize(root, app=nil)
      @root = F.expand_path(root)
      @app = app || Rack::File.new(@root)
    end

    def call(env)
      dup._call(env)
    end

    F = ::File

    def _call(env)
      @env = env
      @path_info, @script_name = env.values_at('PATH_INFO', 'SCRIPT_NAME')

      if forbidden = check_forbidden
        forbidden
      else
        @path = F.join(@root, Utils.unescape(@path_info))
        list_path
      end
    end

    def check_forbidden
      return unless @path_info.include? ".."

      body = "Forbidden\n"
      size = body.respond_to?(:bytesize) ? body.bytesize : body.size
      return [403, {"Content-Type" => "text/plain","Content-Length" => size.to_s}, [body]]
    end

    def list_directory
      @files = [['../','Parent Directory','','','']]
      glob = F.join(@path, '*')

      Dir[glob].sort.each do |node|
        name, stat = stat(node)
        next unless name and stat
        basename = F.basename(node)
        ext = F.extname(name)

        url = F.join(@script_name, @path_info, basename)
        size = stat.size
        type = stat.directory? ? 'directory' : Utils.mime_type(ext)
        size = stat.directory? ? '-' : filesize_format(size)
        mtime = stat.mtime.httpdate

        @files << [ url, basename, size, type, mtime ]
      end

      return [ 200, {'Content-Type'=>'text/html; charset=utf-8'}, self ]
    end

    # Get File.stat from the specified node (file/directory), follow symlinks
    # up to 10 times before (most likely) failing by calling stat for the symlink.
    # This avoids circular symlinks from taking over your system.
    #
    # We also return the filename the symlink resolves to, this is only used to
    # determine the original extension for the mime type

    def stat(node, max = 10)
      if F.symlink?(node) and max > 0
        stat(F.readlink(node), max - 1)
      else
        [node, F.stat(node)]
      end
    rescue Errno::ENOENT => ex
      return nil
    end

    # TODO: add correct response if not readable, not sure if 404 is the best
    #       option
    def list_path
      @stat = F.stat(@path)

      if @stat.readable?
        return @app.call(@env) if @stat.file?
        return list_directory if @stat.directory?
      else
        raise Errno::ENOENT, 'No such file or directory'
      end

    rescue Errno::ENOENT => exception
      return entity_not_found
    end

    def entity_not_found
      body = "Entity not found: #{@path_info}\n"
      size = body.respond_to?(:bytesize) ? body.bytesize : body.size
      return [404, {"Content-Type" => "text/plain", "Content-Length" => size.to_s}, [body]]
    end

    def each
      show_path = @path.sub(/^#{@root}/,'')
      files = @files.map{|f| DIR_FILE % f }*"\n"
      page  = DIR_PAGE % [ show_path, show_path , files ]
      page.each_line{|l| yield l }
    end

    def each_entry
      @files.each{|e| yield e }
    end

    # Stolen from Ramaze

    FILESIZE_FORMAT = [
      ['%.1fT', 1 << 40],
      ['%.1fG', 1 << 30],
      ['%.1fM', 1 << 20],
      ['%.1fK', 1 << 10],
    ]

    def filesize_format(int)
      FILESIZE_FORMAT.each do |format, size|
        return format % (int.to_f / size) if int >= size
      end

      int.to_s + 'B'
    end
  end
end
