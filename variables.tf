################################################################################
# Variables
################################################################################

variable "node_name" {
  description = "Name for the lab container / node"
  type        = string
  default     = "devops-sre-lab"
}

variable "base_image" {
  description = "Base Docker image (must support systemd)"
  type        = string
  default     = "jrei/systemd-ubuntu:22.04"
}

variable "k8s_version" {
  description = "Kubernetes stable channel version (e.g. v1.35)"
  type        = string
  default     = "v1.35"
}

variable "pod_cidr" {
  description = "Pod network CIDR for kubeadm / Flannel"
  type        = string
  default     = "10.244.0.0/16"
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB L2 address pool"
  type        = string
  default     = "172.20.0.200-172.20.0.210"
}
