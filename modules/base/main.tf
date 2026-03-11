################################################################################
# Module: base
# Spins up a systemd-enabled Ubuntu container that acts as the "VM"
################################################################################

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

################################################################################
# Pull base image
################################################################################

resource "docker_image" "base" {
  name         = var.image_name
  keep_locally = true
}

################################################################################
# Lab container
# — privileged + cgroupns=host so that containerd / k8s can run inside
################################################################################

resource "docker_container" "lab" {
  name  = var.node_name
  image = docker_image.base.image_id

  # Systemd needs /sys/fs/cgroup
  privileged = true

  cgroupns_mode = "host"

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
    read_only      = false
  }

  # Persistent storage for k8s etcd and docker layers
  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/docker"
  }

  volumes {
    volume_name    = docker_volume.k8s.name
    container_path = "/var/lib/kubelet"
  }

  # Expose Jenkins
  ports {
    internal = 8080
    external = 8080
    protocol = "tcp"
  }

  # Expose Grafana port-forward target
  ports {
    internal = 3000
    external = 3000
    protocol = "tcp"
  }

  networks_advanced {
    name = var.network_name
  }

  # Keep stdin open so systemd PID1 doesn't exit
  stdin_open = true
  tty        = true

  # Systemd as PID 1
  command = ["/lib/systemd/systemd"]

  # Increase inotify limits needed by k8s
  ulimit {
    name = "nofile"
    soft = 65536
    hard = 65536
  }

  lifecycle {
    ignore_changes = [command]
  }
}

################################################################################
# Persistent volumes
################################################################################

resource "docker_volume" "data" {
  name = "${var.node_name}-docker-data"
}

resource "docker_volume" "k8s" {
  name = "${var.node_name}-k8s-data"
}

################################################################################
# Install base packages
################################################################################

resource "null_resource" "base_packages" {
  triggers = {
    container_id = docker_container.lab.id
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update -y",
      "apt-get upgrade -y",
      "apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common jq git vim wget build-essential",
      # Disable swap
      "swapoff -a",
      "sed -i '/ swap / s/^/#/' /etc/fstab",
    ]

    connection {
      type = "docker"
      host = docker_container.lab.id
    }
  }
}
