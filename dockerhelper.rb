class DockerHelper
  attr :c

  def initialize(common)
    @c = common
  end

  def requires_docker()
    status = c.run %W{which docker}
    unless status.success?
      c.error "docker not installed."
      STDERR.puts "Installation instructions:"
      STDERR.puts "\n  https://www.docker.com/community-edition\n\n"
      exit 1
    end
    status = c.run %W{docker info}
    unless status.success?
      c.error "`docker info` command failed."
      STDERR.puts "This is usually a permissions problem. Try allowing your user to run docker\n"
      STDERR.puts "without sudo:"
      STDERR.puts "\n$ sudo usermod -aG docker #{ENV["USER"]}\n\n"
      c.error "Note: You will need to log-in to a new shell before this change will take effect.\n"
      exit 1
    end
  end

  def requires_docker_gem()
    begin
      require "docker"
    rescue LoadError
      c.error "Missing docker-api gem. This makes it much easier for this script to communicate\n" \
        "with docker. Please install the gem and then re-run. Try the following to install the gem:"
      STDERR.puts "\n$ sudo gem install docker-api\n\n"
      exit 1
    end
  end

  def image_exists?(name)
    requires_docker_gem
    Docker::Image.exist?(name)
  end

  def ensure_image(name)
    requires_docker_gem
    if not Docker::Image.exist?(name)
      c.error "Missing docker image \"#{name}\". Pulling..."
      c.run_inline(%W{docker pull #{name}})
      c.status "Image \"#{name}\" pulled."
    end
  end
end
