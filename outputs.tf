output "public_ip_address" {
  value = data.azurerm_public_ip.cicd.ip_address
  description = "The public IP address of the CI/CD VM."
}