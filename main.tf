################################################################################
# DevOps + SRE Lab — Local Testing Environment
# Provider: docker (local VM via Docker-in-Docker / systemd container)
# Run: terraform init && terraform apply
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

################################################################################
# NETWORKING
################################################################################

resource "docker_network" "lab" {
  name            = "devops-lab"
  driver          = "bridge"
  attachable      = true

  ipam_config {
    subnet  = "172.20.0.0/24"
    gateway = "172.20.0.1"
  }
}

################################################################################
# MODULES
################################################################################

module "base_node" {
  source = "./modules/base"

  network_name = docker_network.lab.name
  node_name    = var.node_name
  image_name   = var.base_image
}

module "kubernetes" {
  source = "./modules/kubernetes"

  container_id   = module.base_node.container_id
  container_name = module.base_node.container_name
  k8s_version    = var.k8s_version
  pod_cidr       = var.pod_cidr

  depends_on = [module.base_node]
}

module "jenkins" {
  source = "./modules/jenkins"

  container_id   = module.base_node.container_id
  container_name = module.base_node.container_name

  depends_on = [module.kubernetes]
}

module "monitoring" {
  source = "./modules/monitoring"

  container_id   = module.base_node.container_id
  container_name = module.base_node.container_name

  depends_on = [module.jenkins]
}

module "networking" {
  source = "./modules/networking"

  container_id   = module.base_node.container_id
  container_name = module.base_node.container_name
  metallb_range  = var.metallb_ip_range

  depends_on = [module.monitoring]
}
