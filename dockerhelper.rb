class DockerHelper
  attr :c

  def initialize(common)
    @c = common
  end

  def requires_docker()
    status = c.run %W{which docker}
    unless status.success?
      error "docker not installed."
      STDERR.puts "Installation instructions:"
      STDERR.puts "  https://www.docker.com/community-edition"
      exit 1
    end
  end

  def requires_docker_gem()
    begin
      require "docker"
    rescue LoadError
      c.error "Missing docker gem. Installing..."
      c.run_inline "sudo gem install docker-api"
      c.status "Docker gem installed. Restart to continue."
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
