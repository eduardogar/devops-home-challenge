terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

locals {
  local_registry = "host.docker.internal:5000"
}

# Use the Unix socket available in WSL
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "null_resource" "minikube_start" {
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      # Be strict; tolerate shells without pipefail
      set -eu
      set -o pipefail >/dev/null 2>&1 || true

      # 1) Start Minikube (Docker runtime) and allow your local HTTP registry
      minikube start --profile=devops-challenge --driver=docker --container-runtime=docker --kubernetes-version=v1.28.3 --memory=6144 --cpus=4 --v=9 --insecure-registry=host.docker.internal:5000

      # 2) If the node's Docker doesn't show the registry, add a systemd drop-in and restart
      if ! minikube ssh -p devops-challenge -- docker info 2>/dev/null | grep -q "host.docker.internal:5000"; then
        echo "Registry host.docker.internal:5000 not listed; creating drop-in on the node..."

        # Run a privileged script inside the node (no Terraform interpolation inside this block)
        minikube ssh -p devops-challenge -- "sudo REG='host.docker.internal:5000' bash -s" <<'SCRIPT'
set -eu
set -o pipefail >/dev/null 2>&1 || true

# Remove conflicting JSON config if present
rm -f /etc/docker/daemon.json || true

# Find docker.service unit and extract ExecStart (no DBus required)
UNIT=""
for f in /etc/systemd/system/docker.service /lib/systemd/system/docker.service /usr/lib/systemd/system/docker.service; do
  [ -f "$f" ] && UNIT="$f" && break
done
[ -n "$UNIT" ] || { echo "docker.service unit not found"; exit 1; }

CUR="$(sed -n 's/^ExecStart=//p' "$UNIT" | tail -n1)"

mkdir -p /etc/systemd/system/docker.service.d
printf "[Service]\nExecStart=\nExecStart=%s --insecure-registry=%s\n" "$CUR" "$REG" \
  > /etc/systemd/system/docker.service.d/99-insecure-registry.conf

systemctl daemon-reload
systemctl restart docker
systemctl restart cri-docker || systemctl restart cri-dockerd || true
systemctl restart kubelet || true
SCRIPT
      fi

      # 3) Sanity checks
      minikube ssh -p devops-challenge -- 'docker info 2>/dev/null | sed -n "/Insecure Registries/,+4p"'
      curl -sI http://host.docker.internal:5000/v2/ || true
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-lc"]
    command     = "minikube delete --profile=devops-challenge || true"
  }
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
    host_path      = "/home/egarcia/.kube-copy"
    container_path = "/var/jenkins_home/.kube"
  }
  
  # Mount the local ~/.minikube directory into the container to get the certificate files
  volumes {
    host_path      = "/home/egarcia/.minikube-copy"
    container_path = "/var/jenkins_home/.minikube"
  }

  volumes {
    volume_name    = docker_volume.jenkins_home.name
    container_path = "/var/jenkins_home"
  }

  # Ensure the Jenkins container waits for Minikube to start
  depends_on = [
    docker_container.local_registry,
    null_resource.minikube_start
  ]
}

resource "docker_volume" "jenkins_home" {
  name = "jenkins_home"
}
