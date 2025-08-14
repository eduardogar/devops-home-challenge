# DevOps Home Challenge – Local Minikube + Jenkins + Registry + Helm

A local, end‑to‑end setup that builds and runs a simple **Python/Flask** web app on **Minikube**. 
Images are built by **Jenkins** and pushed to a **local Docker registry**; the app is exposed through **NGINX Ingress** with a friendly hostname via `/etc/hosts`.

> See **ARCHITECTURE.md** for the system overview and diagrams.

---

## Contents
- [DevOps Home Challenge – Local Minikube + Jenkins + Registry + Helm](#devops-home-challenge--local-minikube--jenkins--registry--helm)
  - [Contents](#contents)
  - [Features](#features)
  - [Repo Structure](#repo-structure)
  - [Prerequisites](#prerequisites)
  - [Quick Start (Everything via Terraform + Helm)](#quick-start-everything-via-terraform--helm)
    - [Start infrastructure](#start-infrastructure)
  - [CI/CD with Jenkins](#cicd-with-jenkins)
    - [Configure a Pipeline job](#configure-a-pipeline-job)
    - [Map hostname via /etc/hosts](#map-hostname-via-etchosts)
  - [Verification](#verification)
  - [Troubleshooting \& Tips](#troubleshooting--tips)
  - [Evidence of Working Solution](#evidence-of-working-solution)
  - [Clean Up](#clean-up)

---

## Features
- **Python app** (`my-app.py`) exposes `/`, `/status`, `/health` on port **8000**.
- **Helm chart** to deploy `Deployment` + `Service` + `Ingress` + `ConfigMap`.
- **NGINX Ingress** exposed via a `LoadBalancer` on Minikube with `minikube tunnel`.
- **Local registry** (e.g., `host.docker.internal:5000`) for image publishing.
- **Jenkins** pipeline (**Jenkinsfile**) builds, pushes, and deploys.
- **Terraform** provisions local infra (registry, Jenkins container, and Minikube bootstrap).

---

## Repo Structure
```
devops-challenge/
│
├── README.md                    # Main documentation
├── ARCHITECTURE.md              # Architecture decisions
│
├── terraform/                   # Infrastructure as Code
│   └── main.tf
│
├── jenkins/                     # CI/CD Configuration
│   ├── Jenkinsfile              # Main pipeline
│   └──Dockerfile                # Docker image for the Jenkins server
│
├── kubernetes/                  # K8s Deployments
│   └── helm-chart/              # Helm chart (if chosen)
│       ├── Chart.yaml           # Helm chart metadata
│       ├── values.yaml          # Helm values (override via --set as needed)
│       └── templates/           # Contains k8s yaml files
│
├── application/                 # Sample Application
│   ├── my-app.py                # Application source code
│   ├── Dockerfile               # Application image
│   └── requirements.txt         # Flask
│
└── docs/                        # Additional documentation
    └── evidence/                # Screenshots showing succesful operation
```

---

## Prerequisites
- Docker Engine (Linux) or Docker Desktop (macOS/Windows). Ensure the Docker socket is accessible.
- **kubectl**, **Helm**, **Minikube**, **Terraform >= 1.5**.
- Enough local resources (suggested: 2 vCPU, 4–6 GB RAM for Minikube).

> **Linux/WSL note**: `host.docker.internal` may not resolve. Use `localhost:5000` or your host IP. If using an **HTTP** registry, configure Docker **insecure-registries** accordingly.

---

## Quick Start (Everything via Terraform + Helm)

This path uses `main.tf` to spin up: local Docker registry, Jenkins container (with tools), and bootstrap Minikube. Then you deploy the chart.

### Start infrastructure
```bash
terraform init
terraform apply -auto-approve
```

- Access Jenkins at **http://localhost:8080** (first run shows the unlock token in container logs).
- A local registry is created at **host.docker.internal:5000** (or switch to `localhost:5000`).


---

## CI/CD with Jenkins

Jenkins is provisioned locally (via Terraform) as a Docker container with `kubectl`, `helm`, and `minikube` preinstalled (see **Dockerfile**). The pipeline lives in **Jenkinsfile** and does:

1. **Checkout** repo (`REPO_URL`, `BRANCH_NAME`).
2. **Build** Docker image:  
   - `${REGISTRY_URL}/${APP_NAME}:${BUILD_NUMBER}`  
   - `${REGISTRY_URL}/${APP_NAME}:latest`
3. **Push** both tags to the **local registry**.
4. **Deploy** (Helm or kubectl) using the just-built image/tag.
5. **Post‑deploy checks** (kubectl get/curl).

### Configure a Pipeline job
- In Jenkins, create a **Multibranch Pipeline** or a **Pipeline** that points to this repo (script path `Jenkinsfile`).
- Set/verify environment variables in the job or Jenkinsfile:
  - `REGISTRY_URL` (default: `host.docker.internal:5000`)
  - `APP_NAME` (default: `devops-challenge-app`)
- Ensure the Jenkins container can reach the Docker socket (`/var/run/docker.sock`) and has access to Minikube kubeconfig/certs (mounted by Terraform under `/var/jenkins_home/.minikube`).


---

### Map hostname via /etc/hosts
Get the external IP for the ingress controller:
```bash
IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); echo $IP
```

Add to `/etc/hosts`:
```
<IP_FROM_ABOVE>  my-app.local
```

Open: **http://my-app.local/** and **http://my-app.local/status**.

---

## Verification

After a deploy:
```bash
# Replace NS if different
kubectl -n staging get pods,svc,ingress

# Check the app JSON
IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: my-app.local" "http://$IP/status"
```

Expected `/status` response shape:
```json
{
  "status": "ok",
  "hostname": "...",
  "platform": "...",
  "app_version": "v1.0.0"
}
```

---

## Troubleshooting & Tips

- **Ingress host not resolving** → Confirm `minikube tunnel` is running and `/etc/hosts` contains `my-app.local` → external IP.
- **Image pull fails from local registry** → On Linux, consider `localhost:5000` and configure Docker **insecure-registries**. Re-tag and push.
- **Ports mismatch** → App listens on **8000**. Set `--set service.targetPort=8000` so Service forwards correctly.
- **Jenkins can’t deploy** → Verify the `.minikube` mount into Jenkins and `kubectl config current-context` inside the container.
- **nginx: service-upstream** → If routing is flaky locally, add annotation:  
  `--set-string ingress.annotations.'nginx\.ingress\.kubernetes\.io/service-upstream'="true"`
- **Windows/WSL** → `host.docker.internal` may not exist. Use `localhost:5000` or your host IP for `REGISTRY_URL`.

---

## Evidence of Working Solution

Create a simple log with commands and outputs (or screenshots) showing the app is live:

```bash
# 1) Pods/Services/Ingress
kubectl -n staging get pods,svc,ingress -o wide

# 2) Ingress IP
kubectl -n ingress-nginx get svc ingress-nginx-controller

# 3) App endpoints
curl -i http://my-app.local/
curl -i http://my-app.local/status

# 4) Rolling update demo (optional)
helm upgrade my-app . -n staging --set config.welcomeMessage="Updated via Helm"
```

---

## Clean Up
```bash
# Remove the release
helm uninstall my-app -n staging || true

# Remove ingress controller
helm uninstall ingress-nginx -n ingress-nginx || true

# Tear down local infra
terraform destroy -auto-approve || true
```

---

