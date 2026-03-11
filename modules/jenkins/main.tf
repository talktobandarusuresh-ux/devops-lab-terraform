################################################################################
# Module: jenkins
# Installs: OpenJDK 17, Jenkins LTS, kubernetes / pipeline / git plugins
################################################################################

terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

################################################################################
# 1 — Java 17
################################################################################

resource "null_resource" "java" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "apt-get install -y openjdk-17-jdk",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }
}

################################################################################
# 2 — Jenkins LTS
################################################################################

resource "null_resource" "jenkins_install" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /usr/share/keyrings",
      "curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null",
      "echo \"deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/\" > /etc/apt/sources.list.d/jenkins.list",
      "apt-get update -y",
      "apt-get install -y jenkins",
      "systemctl enable jenkins",
      "systemctl start jenkins",
      # Allow Jenkins to run Docker builds
      "usermod -aG docker jenkins",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.java]
}

################################################################################
# 3 — Wait for Jenkins to be ready
################################################################################

resource "null_resource" "jenkins_ready" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for Jenkins to start...'",
      "for i in $(seq 1 30); do curl -s http://localhost:8080/login > /dev/null && echo 'Jenkins ready!' && break; echo \"Attempt $i/30...\"; sleep 10; done",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.jenkins_install]
}

################################################################################
# 4 — Jenkins plugins
#   kubernetes, workflow-aggregator (Pipeline), git
################################################################################

resource "null_resource" "jenkins_plugins" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/jenkins/plugins",
      # Download .hpi files directly
      "curl -sL https://updates.jenkins.io/download/plugins/kubernetes/latest/kubernetes.hpi           -o /var/lib/jenkins/plugins/kubernetes.hpi",
      "curl -sL https://updates.jenkins.io/download/plugins/workflow-aggregator/latest/workflow-aggregator.hpi -o /var/lib/jenkins/plugins/workflow-aggregator.hpi",
      "curl -sL https://updates.jenkins.io/download/plugins/git/latest/git.hpi                         -o /var/lib/jenkins/plugins/git.hpi",
      "chown -R jenkins:jenkins /var/lib/jenkins/plugins",
      "systemctl restart jenkins",
      # Wait again after restart
      "sleep 20",
      "for i in $(seq 1 20); do curl -s http://localhost:8080/login > /dev/null && echo 'Jenkins restarted OK' && break; sleep 10; done",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.jenkins_ready]
}

################################################################################
# 5 — Print initial password to state log
################################################################################

resource "null_resource" "jenkins_password" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "echo '========== Jenkins Initial Admin Password =========='",
      "cat /var/lib/jenkins/secrets/initialAdminPassword",
      "echo '===================================================='",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.jenkins_plugins]
}
