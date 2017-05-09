require "open3"

class SyncFiles
  attr :c

  def initialize(common)
    @c = common
  end

  def shared_vol()
    env = c.load_env
    "#{env.namespace}-src"
  end

  def log_file_name()
    ".rsync.log"
  end

  def get_dest_path(src, dst)
    if dst.nil?
      dst = src
    end
    dst = dst.split(/\//).reverse.drop(1).reverse.join("/")
    if not dst.empty?
      dst = "/w/#{dst}"
    else
      dst = "/w"
    end
  end

  def start_rsync_container()
    env = c.load_env
    c.docker.requires_docker
    c.docker.ensure_image("tjamet/rsync")
    c.run_inline %W{
      docker run -d
        --name #{env.namespace}-rsync
        -v #{shared_vol}:/w
        -e DAEMON=docker
        tjamet/rsync
    }
  end

  def stop_rsync_container()
    env = c.load_env
    c.run_inline %W{docker rm -f #{env.namespace}-rsync}
  end

  def ensure_dest_dir(dst)
    c.run_inline %W{docker run --rm -v #{shared_vol}:/w tjamet/rsync mkdir -p /w/#{dst}}
  end

  def rsync_path(src, dst, log)
    env = c.load_env
    dst = get_dest_path(src, dst)
    rsync_remote_shell = "docker exec -i"
    cmd = %W{
      rsync --blocking-io -azlv --delete -e #{rsync_remote_shell}
        #{src}
        #{env.namespace}-rsync:#{dst}
    }
    if log
      Open3.popen3(*cmd) do |i, o, e, t|
        i.close
        if not t.value.success?
          c.error e.read
          exit t.value.exitstatus
        end
        File.open(log_file_name, "a") do |file|
          file.write o.read
        end
      end
    else
      c.run_inline cmd
    end
  end

  def requires_fswatch()
    status = c.run %W{which fswatch}
    unless status.success?
      c.error "fswatch not installed."
      STDERR.puts "Try brew install fswatch"
      exit 1
    end
  end

  def watch_path(src, dst)
    Open3.popen3(*%W{fswatch -o #{src}}) do |stdin, stdout, stderr, thread|
      Thread.current["pid"] = thread.pid
      stdin.close
      stdout.each_line do |_|
        rsync_path src, dst, true
      end
    end
  end

  def perform_initial_sync()
    env = c.load_env
    env.source_file_paths.each do |src_path|
      rsync_path src_path, nil, false
    end
    ensure_dest_dir env.static_file_dest
    Dir.foreach(env.static_file_src) do |entry|
      unless entry.start_with?(".")
        rsync_path "#{env.static_file_src}/#{entry}", "#{env.static_file_dest}/#{entry}", false
      end
    end
  end

  def start_watching_sync()
    requires_fswatch
    env = c.load_env
    File.open(log_file_name, "w") {} # Create and truncate if exists.
    env.source_file_paths.each do |src_path|
      thread = Thread.new { watch_path src_path, nil }
      at_exit {
        Process.kill("HUP", thread["pid"])
        thread.join
      }
    end
    Dir.foreach(env.static_file_src) do |entry|
      unless entry.start_with?(".")
        thread = Thread.new {
          watch_path "#{env.static_file_src}/#{entry}", "#{env.static_file_dest}/#{entry}"
        }
        at_exit {
          Process.kill("HUP", thread["pid"])
          thread.join
        }
      end
    end
  end
end
