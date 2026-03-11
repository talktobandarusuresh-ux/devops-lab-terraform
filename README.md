# DevOps + SRE Lab — Terraform (Local)

A fully self-contained local learning environment that mirrors the original bash
script, expressed as Terraform modules. Everything runs inside a **single
privileged Docker container** that acts as a lightweight VM with systemd as PID 1.

---

## What Gets Installed

| Layer | Tools |
|---|---|
| **Container runtime** | containerd (SystemdCgroup), Docker CE + Compose |
| **Kubernetes** | kubeadm · kubelet · kubectl (v1.35) · Flannel CNI |
| **Cluster add-ons** | Metrics Server · Helm 3 |
| **IaC** | Terraform CLI |
| **TUI** | k9s |
| **CI/CD** | Jenkins LTS · OpenJDK 17 · kubernetes / pipeline / git plugins |
| **Monitoring** | kube-prometheus-stack (Prometheus + Grafana + Alertmanager) |
| **Logging** | Loki stack |
| **Tracing** | OpenTelemetry Collector |
| **Probing** | Prometheus Blackbox Exporter |
| **Dashboards** | SRE Golden Signals (Latency, Traffic, Errors, Saturation) |
| **SLOs** | PrometheusRule — HTTP availability (99.9 % target) |
| **Ingress** | ingress-nginx (NodePort) |
| **LB** | MetalLB v0.14 (L2 mode) |
| **TLS** | cert-manager + self-signed ClusterIssuer |

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker Desktop / Docker Engine | Privileged containers must be allowed |
| Terraform ≥ 1.5 | `brew install terraform` / `apt install terraform` |
| 8 GB RAM free | kube-prometheus-stack alone needs ~3–4 GB |
| ~20 GB disk | Images + etcd + Docker layers |

---

## Quick Start

```bash
# 1. Clone / unzip the project
cd devops-lab-terraform

# 2. Initialise providers
terraform init

# 3. Review the plan
terraform plan

# 4. Apply  (takes ~15–25 min on first run)
terraform apply

# 5. Watch progress live in another terminal
docker logs -f devops-sre-lab
```

After `apply` succeeds, Terraform prints all useful access commands as outputs.

---

## Accessing the Tools

### Jenkins
```bash
open http://localhost:8080
# Get password:
docker exec devops-sre-lab cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Grafana
```bash
# Port-forward from inside the container to your laptop
docker exec devops-sre-lab \
  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address 0.0.0.0 &
open http://localhost:3000
# Default creds: admin / prom-operator
```

### k9s (Kubernetes TUI)
```bash
docker exec -it devops-sre-lab k9s
```

### kubectl from your host
```bash
docker cp devops-sre-lab:/root/.kube/config ~/.kube/config-lab
export KUBECONFIG=~/.kube/config-lab
kubectl get nodes
```

### Prometheus
```bash
docker exec devops-sre-lab \
  kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090 --address 0.0.0.0 &
open http://localhost:9090
```

---

## Project Structure

```
devops-lab-terraform/
├── main.tf               # Root module — wires everything together
├── variables.tf          # Top-level variables (image, k8s version, CIDRs …)
├── outputs.tf            # Access URLs & helper commands
└── modules/
    ├── base/             # Docker container + volume + base packages
    ├── kubernetes/       # containerd, Docker, kubeadm, Helm, Terraform, k9s
    ├── jenkins/          # Java 17, Jenkins, plugins
    ├── monitoring/       # Prometheus, Grafana, Loki, OTel, Blackbox, SLOs
    └── networking/       # Nginx Ingress, MetalLB, cert-manager
```

---

## Customising

Edit `variables.tf` or pass `-var` flags:

```bash
# Use a different k8s version
terraform apply -var="k8s_version=v1.30"

# Change MetalLB IP pool (must be in 172.20.0.0/24)
terraform apply -var="metallb_ip_range=172.20.0.220-172.20.0.230"
```

---

## Teardown

```bash
terraform destroy
```

This removes the container and its volumes — a completely clean slate.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `kubeadm init` fails with preflight errors | The `--ignore-preflight-errors=all` flag is set; check `docker logs devops-sre-lab` for details |
| Pods stuck in `Pending` | Flannel may still be starting — wait 2 min or run `kubectl get pods -A` |
| Metrics-server CrashLoop | The `--kubelet-insecure-tls` patch is applied automatically |
| Jenkins never becomes ready | Increase `sleep` delays in `jenkins/main.tf` if host is slow |
| MetalLB IPs unreachable from host | Expected in Docker Desktop; use `kubectl port-forward` instead |

---

## Notes on Weave → Flannel

The original script used `cloud.weave.works` which is **permanently offline**.
This Terraform project substitutes **Flannel** (same CIDR: `10.244.0.0/16`),
which is the standard CNI for single-node kubeadm labs.
