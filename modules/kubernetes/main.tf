################################################################################
# Module: kubernetes
# Installs: containerd, Docker CLI, kubeadm/kubelet/kubectl, Helm,
#           Terraform, k9s, Metrics Server
################################################################################

terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

################################################################################
# 1 — Containerd
################################################################################

resource "null_resource" "containerd" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "apt-get install -y containerd",
      "mkdir -p /etc/containerd",
      "containerd config default > /etc/containerd/config.toml",
      "sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "systemctl daemon-reload",
      "systemctl enable containerd",
      "systemctl restart containerd",
    ]
    connection { type = "docker"; host = var.container_id }
  }
}

################################################################################
# 2 — Docker (for CI builds inside Jenkins)
################################################################################

resource "null_resource" "docker" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list",
      "apt-get update -y",
      "apt-get install -y docker-ce docker-ce-cli docker-compose-plugin",
      "systemctl enable docker",
      "systemctl restart docker",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.containerd]
}

################################################################################
# 3 — Kubernetes tools
################################################################################

resource "null_resource" "kubernetes_tools" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/apt/keyrings",
      "curl -fsSL https://pkgs.k8s.io/core:/stable:/${var.k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo \"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${var.k8s_version}/deb/ /\" > /etc/apt/sources.list.d/kubernetes.list",
      "apt-get update -y",
      "apt-get install -y kubelet kubeadm kubectl",
      "apt-mark hold kubelet kubeadm kubectl",
      "systemctl enable kubelet",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.docker]
}

################################################################################
# 4 — Kernel / sysctl prerequisites for kubeadm
################################################################################

resource "null_resource" "sysctl" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "modprobe overlay || true",
      "modprobe br_netfilter || true",
      "cat <<'EOF' > /etc/sysctl.d/k8s.conf\nnet.bridge.bridge-nf-call-iptables  = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward                 = 1\nEOF",
      "sysctl --system",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.kubernetes_tools]
}

################################################################################
# 5 — kubeadm init
################################################################################

resource "null_resource" "kubeadm_init" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      # Init with flannel CIDR
      "kubeadm init --pod-network-cidr=${var.pod_cidr} --ignore-preflight-errors=all 2>&1 | tee /root/kubeadm-init.log",
      # Configure kubectl for root
      "mkdir -p $HOME/.kube",
      "cp /etc/kubernetes/admin.conf $HOME/.kube/config",
      "chown $(id -u):$(id -g) $HOME/.kube/config",
      # Remove control-plane taint so pods can schedule on single node
      "kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.sysctl]
}

################################################################################
# 6 — Flannel CNI  (replaces weave which is deprecated)
################################################################################

resource "null_resource" "flannel" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml",
      # Wait until coredns is running
      "kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=180s",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.kubeadm_init]
}

################################################################################
# 7 — Helm
################################################################################

resource "null_resource" "helm" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.flannel]
}

################################################################################
# 8 — Terraform CLI
################################################################################

resource "null_resource" "terraform_cli" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg",
      "echo \"deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list",
      "apt-get update -y",
      "apt-get install -y terraform",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.helm]
}

################################################################################
# 9 — k9s
################################################################################

resource "null_resource" "k9s" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')",
      "wget -q https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/k9s_Linux_amd64.tar.gz",
      "tar -xzf k9s_Linux_amd64.tar.gz",
      "mv k9s /usr/local/bin/",
      "rm -f k9s_Linux_amd64.tar.gz",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.terraform_cli]
}

################################################################################
# 10 — Metrics Server
################################################################################

resource "null_resource" "metrics_server" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",
      # Patch for single-node (insecure TLS) — common local lab requirement
      "kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'",
    ]
    connection { type = "docker"; host = var.container_id }
  }

  depends_on = [null_resource.k9s]
}
