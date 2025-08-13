DevOps Home Challenge — Local (Terraform • Jenkins • Minikube • Helm)

This repository provisions a local CI/CD playground that builds and deploys a small status/health API to a Minikube cluster using Jenkins and Helm. 
It’s designed for fast iteration and for demonstrating DevOps fundamentals end‑to‑end.

**Tech Stack**

    Terraform (Docker provider, local‑exec)

    Docker & local Registry (registry:2 on port 5000)

    Jenkins (Pipeline: tfsec → build → trivy → helm → deploy)

    Minikube (Docker driver)

    Helm (single chart, staging & production)

**Repository Map (key paths)**

    terraform/            # Minikube + local registry + Jenkins
    jenkins/              # Jenkinsfile, scripts, plugins
    kubernetes/helm-chart # Chart + templates
    application/          # Sample API + Dockerfile
    scripts/              # Helpers (setup-local.sh, deploy.sh, cleanup.sh)
    docs/                 # Extra docs, images

**Quickstart (TL;DR)**

    # 1) Clone
    git clone https://github.com/eduardogar/devops-home-challenge.git
    cd devops-home-challenge/terraform

    # 2) Provision local infra (registry + Jenkins + Minikube)
    terraform init
    terraform apply -auto-approve

    # 3) Open Jenkins and run the pipeline
    #    http://localhost:8080  (get initial admin password from container logs)


**Accessing the App (staging)**

    The chart installs a Service named after the release (e.g., my-app-staging). Use port‑forwarding during local dev.

    kubectl -n staging get svc
    kubectl -n staging port-forward svc/my-app-staging 8081:80
    curl http://localhost:8081/           # welcome/info
    curl http://localhost:8081/health     # health check (example)
    curl http://localhost:8081/status     # status (example)


**CI/CD overview**

    Build: Docker image tagged host.docker.internal:5000/devops-challenge-app:<BUILD_NUMBER>

    Scan: IaC with tfsec, image with Trivy (non‑blocking locally)

    Deploy: Helm → staging (auto), manual approval, then Helm → production using tag stable

    Rollback: helm -n production history my-app-production then helm -n production rollback my-app-production <REV>


**Common Issues**

    host.docker.internal unreachable inside Linux containers: update Docker Engine (20.10+) or add --add-host=host.docker.internal:host-gateway to Docker runs; for Minikube pulls, ensure the cluster is started with --insecure-registry=host.docker.internal:5000.

    Jenkins can’t reach kube API: verify volumes ~/.kube and ~/.minikube are mounted into the Jenkins container and the pipeline’s kubeconfig step ran.

    Image pull errors in cluster: check that the registry container is up, and that the image exists: curl -s http://localhost:5000/v2/_catalog.