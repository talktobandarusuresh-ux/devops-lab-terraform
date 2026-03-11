################################################################################
# Module: networking
# Installs via Helm / manifests:
#   - ingress-nginx   (NodePort for local access)
#   - MetalLB         (L2 load balancer)
#   - cert-manager    (TLS certificate management)
#   - ClusterIssuer   (self-signed, for lab use)
################################################################################

terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

################################################################################
# 1 — ingress-nginx
################################################################################

resource "null_resource" "ingress_nginx" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx",
      "helm repo update",
      "kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -",
      "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --set controller.service.type=NodePort --wait --timeout 5m",
    ]
    connection { type = "docker"; host = var.container_id }
  }
}

################################################################################
# 2 — MetalLB
################################################################################

resource "null_resource" "metallb" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml",
      "kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s",
      <<-SCRIPT
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - ${var.metallb_range}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-advert
  namespace: metallb-system
EOF
SCRIPT
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.ingress_nginx]
}

################################################################################
# 3 — cert-manager
################################################################################

resource "null_resource" "cert_manager" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm repo add jetstack https://charts.jetstack.io",
      "helm repo update",
      "kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -",
      "helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --set installCRDs=true --wait --timeout 5m",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.metallb]
}

################################################################################
# 4 — Self-signed ClusterIssuer  (ready-to-use TLS for lab services)
################################################################################

resource "null_resource" "selfsigned_issuer" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      # Give cert-manager webhook a moment to become ready
      "sleep 15",
      <<-SCRIPT
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF
SCRIPT
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.cert_manager]
}
