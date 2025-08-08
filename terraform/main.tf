terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Use the Unix socket available in WSL
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Local registry
resource "docker_image" "registry_image" {
  name = "registry:2"
}

resource "docker_container" "local_registry" {
  name  = "local-registry"
  image = docker_image.registry_image.name

  ports {
    internal = 5000
    external = 5000
  }
}

# Build your Jenkins image from ../jenkins/Dockerfile (relative to terraform/)
resource "docker_image" "jenkins_image" {
  name = "my-jenkins-docker-enabled:latest"
  build { context = "../jenkins" }
}

# Run Jenkins; mount Docker socket, kubeconfig, and Minikube certs
resource "docker_container" "jenkins_server" {
  name  = "jenkins"
  image = docker_image.jenkins_image.name

  # Easiest for local dev to avoid socket perms:
  user = "0:0"

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  # Mount the local ~/.kube directory into the container
  volumes {
    host_path      = "/home/egarcia/.kube"
    container_path = "/var/jenkins_home/.kube"
  }
  
  # Mount the local ~/.minikube directory into the container to get the certificate files
  volumes {
    host_path      = "/home/egarcia/.minikube"
    container_path = "/var/jenkins_home/.minikube"
  }

  volumes {
    volume_name    = docker_volume.jenkins_home.name
    container_path = "/var/jenkins_home"
  }

  depends_on = [docker_container.local_registry]
}

resource "docker_volume" "jenkins_home" {
  name = "jenkins_home"
}
