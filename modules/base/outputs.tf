output "container_id" {
  value = docker_container.lab.id
}

output "container_name" {
  value = docker_container.lab.name
}

output "container_ip" {
  value = docker_container.lab.network_data[0].ip_address
}
