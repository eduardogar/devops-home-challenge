**Prerequisites**

    OS: Linux or Windows 10/11 with WSL2 (Ubuntu)

    Docker Engine: 20.10+

    Terraform: 1.5+

    kubectl: 1.28+

    Minikube: 1.36+

    Helm: 3.14+

    tfsec, Trivy, Git


1) Clone the repo

    git clone https://github.com/eduardogar/devops-home-challenge.git
    cd devops-home-challenge

2) Configure local paths (if needed)

    The Terraform config mounts your host ~/.kube and ~/.minikube into the Jenkins container. If your home path/user differs from what’s in terraform/main.tf, adjust those two volume entries to point to your actual locations.

3) Provision infra

    cd terraform
    terraform init
    terraform apply -auto-approve

    What this does:

    Starts Minikube (--driver=docker, 4 CPUs, 6GB RAM) with insecure‑registry to host.docker.internal:5000

    Runs a local Docker registry on port 5000

    Builds and runs a Jenkins controller container with the Docker socket mounted

4) Open Jenkins

    Visit http://localhost:8080

    Get the initial admin password:

    docker logs jenkins 2>&1 | grep -A2 "Admin password"

    Complete the first‑run wizard (install suggested plugins, or the custom image may already have the ones in jenkins/plugins.txt).

5) Create the Pipeline job

    New Item → Pipeline

    Pipeline script from SCM → Git → URL: https://github.com/eduardogar/devops-home-challenge.git, Branch: main

    Save and Build Now

    Note: the Jenkinsfile includes an explicit Code Checkout stage that cleans and re‑clones. This is intentional to ensure a fresh workspace.

6) Verify deployment

    After the Deploy to Staging stage:

    kubectl -n staging get deploy,svc,pods
    kubectl -n staging port-forward svc/my-app-staging 8081:80
    curl http://localhost:8081/health   # replace with actual route if different

    After approving Deploy to Production:

    kubectl -n production get deploy,svc,pods
    kubectl -n production port-forward svc/my-app-production 8082:80
    curl http://localhost:8082/health

7) Rollback (quick)

    helm -n production history my-app-production
    helm -n production rollback my-app-production <REV>

8) Destroy

    cd terraform
    terraform destroy -auto-approve
    

**Troubleshooting**

    Minikube doesn’t trust registry: ensure Terraform ran the null_resource successfully; re‑run terraform apply and check for the "Insecure Registries" section via minikube ssh -p devops-challenge -- 'docker info | sed -n "/Insecure Registries/,+4p"'.

    Kubeconfig errors in Jenkins: the pipeline writes /var/jenkins_home/.kube/config; confirm the stage ran and that ~/.minikube with certs is mounted.

    Helm lint/template fails: run helm lint kubernetes/helm-chart and helm template ... locally to see chart errors.

