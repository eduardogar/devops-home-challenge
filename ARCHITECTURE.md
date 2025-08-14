# ARCHITECTURE

## Overview
This project is a local, end-to-end DevOps setup that demonstrates how to build, package, and run a simple Python web app on a Kubernetes cluster (Minikube), fronted by NGINX Ingress, with images built by Jenkins and stored in a local Docker registry. Local DNS is handled via an `/etc/hosts` entry for a friendly hostname.

**Key goals**
- Keep everything local and reproducible.
- Show a clear CI/CD deployment flow.
- Use health endpoints and config through standard K8s objects.
- Provision the local tooling with **Terraform** for repeatability.

## High-Level Components
- **Application**: Python/Flask service exposing `/`, `/status`, and `/health` on port **8000**.
- **Container Image**: Built from the app repo into a Docker image.
- **Local Registry**: A Docker Registry running on the host (e.g., `host.docker.internal:5000`).
- **Kubernetes (Minikube)**: Runs the app via a **Deployment**, exposes it internally via a **Service**, and externally via **Ingress**.
- **NGINX Ingress Controller**: Exposed as a **LoadBalancer** service.
- **Jenkins**: Builds, tags, and pushes images; then deploys to Kubernetes (Helm or `kubectl`).
- **Local DNS**: `/etc/hosts` entry binds `my-app.local` (or `my-app-staging.local`) to the Ingress external IP.
- **Terraform**: Provisions the local Docker-based infrastructure (local registry, Jenkins container) and boots Minikube.

## Architecture Diagram (Logical)

```
                         +---------------------------+
                         |   Local Docker Registry   |
                         |                           |
                         +-------------+-------------+
                                       ^   pull
                                       |
+----------------------+  push         |                   +----------------------+
|  Jenkins (Docker)    +---------------+                   |  Developer Laptop    |
|  build, tag, push    |                                   |  kubectl/helm/curl   |
+----------+-----------+                                   +----------+-----------+
           ^                                                          |
           |               +---------------------------+              |
           |   deploy      |       Kubernetes          |              |
           +-------------->+         Minikube          +<-------------+
                           |  (Deployment/Service/Ingress)            |
                           +-------------------+----------------------+
                                               |
                                               v
                                         NGINX Ingress (LB)
                                               |
                                               v
                                           my-app.local
                                          (/etc/hosts)

                         [ Provisioning/Orchestration Layer ]
                            +---------------------------+
                            |        Terraform          |
                            |  - kreuzwerker/docker     |
                            |  - null_resource (start)  |
                            +------+--------------------+
                                    |
                                    +--> creates Docker Registry
                                    +--> creates Jenkins container
                                    +--> (starts Minikube before Jenkins via depends_on)
```

## Infrastructure as Code (Terraform)
Terraform is used to provision the local infrastructure for development:

- **Providers & versions**
  - `kreuzwerker/docker ~> 3.0` to manage local Docker resources.
- **Local values**
  - `local.local_registry = "host.docker.internal:5000"` – the registry endpoint used by builds and charts.
- **Docker provider**
  - Uses the Unix socket: `host = "unix:///var/run/docker.sock"`.
- **Resources (excerpt)**
  - `docker_container.local_registry` – runs a local Docker Registry on port **5000**.
  - `docker_volume.jenkins_home` – persistent Jenkins home volume.
  - `docker_container.jenkins_server` – Jenkins LTS container exposing **8080/50000**, mounting:
    - `/var/jenkins_home` (persistent volume).
    - `/var/jenkins_home/.minikube` from the host path **/home/egarcia/.minikube-copy** so Jenkins can access cluster certs/kube files inside the container.
  - `null_resource.minikube_start` – boots Minikube via a local command before Jenkins starts.
  - **Dependency order**: Jenkins container `depends_on = [docker_container.local_registry, null_resource.minikube_start]` so jobs can immediately reach the registry and cluster.

> **Why mount `.minikube` into Jenkins?**  
> This makes `kubectl`/`helm` inside Jenkins aware of the Minikube cluster (certs, kubeconfig path), enabling jobs to deploy without extra manual steps.

### Apply flow
1. `terraform init` installs the Docker provider.
2. `terraform apply`:
   - Starts **Minikube** (via `null_resource`).
   - Creates the **local registry** (port 5000).
   - Creates **Jenkins** with the mounted volume and kube material.
3. Visit Jenkins at `http://localhost:8080` and connect your repo/credentials.

## Kubernetes Objects & How They Fit

### Helm Chart (./Chart.yaml, ./values.yaml, ./templates/*)
A minimal Helm chart defines the app, its version, and resources.

### Deployment (templates/deployment.yaml)
- **Image**: Repository & tag provided by Jenkins or values.
- **Container port**: 8000 (the Flask app listens on 8000).
- **Probes**: HTTP liveness & readiness at `/health` on port 8000.
- **Environment**: `WELCOME_MESSAGE` and `APP_VERSION` from a ConfigMap/value.

### Service (templates/service.yaml)
- **Type**: `ClusterIP` (internal).
- **Ports**: `port: 80` → `targetPort` defaults to the service port.  
  **Recommendation**: set `targetPort: 8000` to match the app.

### Ingress (templates/ingress.yaml)
- **IngressClass**: `nginx`.
- **Host**: `my-app.local` (or `my-app-staging.local`).
- **Annotation**: `nginx.ingress.kubernetes.io/service-upstream: "true"` can improve local routing stability.
- **Backend**: routes traffic to the Service on port 80.

### ConfigMap (templates/configmap.yaml)
- Provides `WELCOME_MESSAGE` (displayed at `/`) and `APP_VERSION` used by `/status` output.

### NGINX Ingress Controller (ingress-nginx-lb.yaml)
- Exposed as a `LoadBalancer` service (`ingress-nginx/ingress-nginx-controller`) on `80/443`.
- On Minikube, allocate an external IP with `minikube tunnel`.

## CI/CD Flow (Jenkins)
1. **Checkout** the repo.
2. **Build** the Docker image, tagging with build number and `latest`:
   - `${REGISTRY_URL}/${APP_NAME}:${BUILD_NUMBER}`
   - `${REGISTRY_URL}/${APP_NAME}:latest`
3. **Push** both tags to the local registry.
4. **Deploy** to Kubernetes using either:
   - **Helm**: `helm upgrade --install ... --set image.repository=${REGISTRY_URL}/${APP_NAME} --set image.tag=${BUILD_NUMBER}`
   - or **kubectl**: apply manifests and update the Deployment image.
5. **Post-deploy check**: `kubectl -n <ns> get pods,svc,ingress` and curl the `/status` endpoint.

## DNS & Access
- Add a hosts entry pointing the Ingress external IP to your hostname:

```
# /etc/hosts
<INGRESS_EXTERNAL_IP>  my-app.local
```

- Get the external IP (after `minikube tunnel` is running):

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
```

- Then open `http://my-app.local/` and `http://my-app.local/status`.

## Verification Checklist
- **Pods healthy**: `kubectl get pods`
- **Probes OK**: liveness/readiness passing on `/health` (port 8000).
- **Service reachable**: `kubectl get svc`
- **Ingress routes**: `kubectl get ingress` and 
  ```bash
  curl -H "Host: my-app.local" http://<INGRESS_EXTERNAL_IP>/status
  ```
- **App JSON**: `/status` returns host, platform, and app version.
- **Config works**: Update ConfigMap value and rollout to see new `WELCOME_MESSAGE` on `/`.

## Security & Ops Considerations
- **Local registry**: If using HTTP, restrict to localhost only, or configure TLS.
- **Resource limits**: Add CPU/memory requests/limits in `values.yaml` to keep the node healthy.
- **Rolling updates**: Deployment strategy handles zero-downtime updates when probes are green.
- **Secrets**: Use `Secret` objects (not ConfigMap) for sensitive data.
- **Namespaces**: Use separate namespaces (e.g., `staging`, `prod`) for isolation.

## Recommendations
- **Align ports**: Set `service.targetPort: 8000` to match the app’s port and avoid confusion.
- **Pin images**: Always deploy the image built in the current pipeline run via explicit `--set image.tag`.
- **Ingress annotation**: Keep `service-upstream: "true"` if it improves stability in your local NGINX ingress; remove if not needed.
- **Terraform outputs**: Export registry URL and Jenkins URL as outputs to reduce manual steps in pipelines.