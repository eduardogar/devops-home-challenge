**Overview**

This project stands up a local, end‑to‑end DevOps lab that builds and ships a simple status/health API to a local Minikube cluster via Jenkins and Helm, with images published to a local Docker registry.

At a glance:

    Infrastructure (Terraform): starts Minikube (Docker driver), a local Docker registry on :5000, and a Jenkins controller container. Minikube is configured to accept the insecure local registry.

    CI/CD (Jenkins): checks out the repo, runs tfsec (IaC scan), builds and tags a Docker image, pushes it to the local registry, runs a Trivy image scan, lints/templates the Helm chart, deploys to staging (auto), then awaits approval before deploying a stable tag to production.

    Kubernetes (Helm): deploys one replica to staging and three replicas to production using the same chart with different values. Service exposure is via Service/NodePort or kubectl port-forward during local dev.

**Diagram**

flowchart LR
  Dev[Developer] -->|git push| GH[GitHub]
  subgraph Local Host
    TF[Terraform] -->|provisions| JN[Jenkins Container]
    TF --> REG[Docker Registry :5000]
    TF --> MK[Minikube (Docker driver)]
  end
  JN -->|checkout| GH
  JN -->|build & push| REG
  JN -->|kubectl/helm| MK
  subgraph Cluster (Minikube)
    STG[staging ns]\nmy-app-staging
    PROD[production ns]\nmy-app-production
  end
  MK --> STG
  MK --> PROD

**Components**

**Terraform**

Uses the docker provider to run two containers:

    registry:2 on host port 5000 (local image store)

    Jenkins custom image (built from jenkins/), running as root for Docker socket access

Runs a null_resource to start Minikube with Docker driver, CPU/memory sizing, and sets insecure registry so the cluster can pull from host.docker.internal:5000.

Mounts host ~/.kube and ~/.minikube into the Jenkins container so the pipeline can talk to the cluster.


**Jenkins Pipeline (high level)**

Stages:

    Code Checkout → clean workspace and clone repo

    IaC Security Scan → tfsec ./terraform

    Configure Kubernetes Context → generate a kubeconfig inside the Jenkins container that points to Minikube (TLS skipped for local), ensure staging/production namespaces exist

    Docker Build & Tag → build image host.docker.internal:5000/devops-challenge-app:<BUILD_NUMBER>, update latest and stable tags

    Image Security Scan → trivy image on the versioned tag (non-failing for local)

    Helm Lint/Template → helm lint and helm template smoke test

    Deploy to Staging → helm upgrade --install my-app-staging ... --namespace staging --set image.tag=$BUILD_NUMBER

    Manual Approval → input gate

    Deploy to Production → helm upgrade --install my-app-production ... --namespace production --set image.tag=stable


**Application**

A small web service exposing three informational routes for status/health/environment. (Confirm exact paths in application/src; examples below.)

Key Decisions & Trade‑offs

    Local registry vs. public registry: local speeds up iteration and avoids credentials, but requires insecure pulls from the cluster. Not for real prod.

    TLS skipped in kubeconfig (local only): simplifies Jenkins/Minikube connectivity at the cost of transport security in dev. In production you would use proper CA/certs.

    Tagging strategy: ephemeral <BUILD_NUMBER> for staging; latest for rolling tag; stable for production. Promotes a previously‑proven image, not the just‑built one.

    Helm over raw YAMLs: chart enables parameterized, repeatable deploys and easy rollbacks. Customize overlays kept optional.

How Code Flows

    Developer pushes to main.

    Jenkins checks out code, scans, builds, and pushes the image to the local registry.

    Helm deploys the new build to staging.

    After validation, a human approves, and Helm deploys the stable tag to production.


Security Considerations (Dev)

    IaC scan with tfsec and image scan with Trivy run on each pipeline.

    No secrets committed; prefer Kubernetes Secrets mounted or env‑injected locally. Use sealed‑secrets or a vault in real environments.

    Local registry is unauthenticated; do not expose beyond localhost.


Limitations / Next Steps

    Switch to Ingress (or a LoadBalancer via minikube addon) to avoid port‑forwarding.

    Replace insecure‑skip‑tls‑verify with proper CA bundle and context.

    Add unit tests and a quick integration smoke test against the staging service before approval.

    Add Git hooks or a multibranch pipeline to build feature branches.