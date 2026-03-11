################################################################################
# Outputs
################################################################################

output "container_name" {
  description = "Lab container name"
  value       = module.base_node.container_name
}

output "container_ip" {
  description = "Lab container IP on devops-lab network"
  value       = module.base_node.container_ip
}

output "jenkins_url" {
  description = "Jenkins web UI"
  value       = "http://${module.base_node.container_ip}:8080"
}

output "jenkins_initial_password_command" {
  description = "Command to retrieve the Jenkins initial admin password"
  value       = "docker exec ${module.base_node.container_name} cat /var/lib/jenkins/secrets/initialAdminPassword"
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig to your host"
  value       = "docker cp ${module.base_node.container_name}:/root/.kube/config ~/.kube/config-devops-lab"
}

output "grafana_access" {
  description = "Port-forward Grafana from inside the container"
  value       = "docker exec ${module.base_node.container_name} kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 --address 0.0.0.0 &"
}

output "k9s_command" {
  description = "Launch k9s inside the container"
  value       = "docker exec -it ${module.base_node.container_name} k9s"
}
