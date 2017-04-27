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
    c.run_inline %W{docker stop #{env.namespace}-rsync}
    c.run_inline %W{docker rm #{env.namespace}-rsync}
  end

  def ensure_path(dst)
    dst = dst.split(/\//).reverse.drop(1).reverse.join("/")
    if not dst.empty?
      c.run_inline %W{docker run --rm -v #{shared_vol}:/w tjamet/rsync mkdir -p /w/#{dst}}
    end
  end

  def rsync_path(src, dst, log)
    env = c.load_env
    if dst.nil?
      dst = src
    end
    dst = dst.split(/\//).reverse.drop(1).reverse.join("/")
    if not dst.empty?
      dst = "/w/#{dst}"
    else
      dst = "/w"
    end
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
      stdin.close
      stdout.each_line do |_|
        rsync_path src, dst, true
      end
    end
  end

  def perform_initial_sync()
    env = c.load_env
    env.source_file_paths.each do |spec|
      if spec.is_a?(Hash)
        spec.each do |k, v|
          ensure_path v
          rsync_path k, v, false
        end
      else
        rsync_path spec, nil, false
      end
    end
  end

  def start_watching_sync()
    requires_fswatch
    env = c.load_env
    File.open(log_file_name, "w") {} # Create and truncate if exists.
    env.source_file_paths.each do |spec|
      if spec.is_a?(Hash)
        spec.each do |k, v|
          thread = Thread.new { watch_path k, v }
          at_exit { thread.exit }
        end
      else
        thread = Thread.new { watch_path spec, nil }
        at_exit { thread.exit }
      end
    end
  end
end
