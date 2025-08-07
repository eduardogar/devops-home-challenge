# 1. Define required providers for Docker and Minikube
terraform {
  required_providers {
    minikube = {
      source = "scott-the-programmer/minikube"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# 2. Provision the Minikube Kubernetes cluster
resource "minikube_cluster" "devops_challenge" {
  cluster_name       = "devops-challenge-cluster"
  driver             = "docker"
  kubernetes_version = "v1.28.3"
  memory             = "6g"
  cpus               = "4"
}

# 3. Provision a local Docker registry
resource "docker_image" "registry_image" {
  name = "registry:2"
}

resource "docker_container" "local_registry" {
  name  = "local-registry"
  image = docker_image.registry_image.image_id
  ports {
    internal = 5000
    external = 5000
  }
}

# 4. Provision the Jenkins server
resource "docker_image" "jenkins_image" {
  name = "my-jenkins-docker-enabled"
}

resource "docker_container" "jenkins_server" {
  name  = "jenkins"
  image = docker_image.jenkins_image.image_id
  ports {
    internal = 8080
    external = 8080
  }
  ports {
    internal = 50000
    external = 50000
  }
  volumes {
    host_path      = "//./pipe/docker_engine"
    container_path = "//./pipe/docker_engine"
  }
  volumes {
    volume_name    = "jenkins_home"
    container_path = "/var/jenkins_home"
  }
}

resource "docker_volume" "jenkins_home" {
  name = "jenkins_home"
}