output "public_ip_id" {
  value = azurerm_public_ip.main.id
}

output "public_ip_address" {
  value = azurerm_public_ip.main.ip_address
}

output "public_url" {
  value = "http://${azurerm_public_ip.main.ip_address}/"
}

output "load_balancer_id" {
  value = azurerm_lb.main.id
}

output "load_balancer_name" {
  value = azurerm_lb.main.name
}

output "lb_backend_pool_id" {
  value = azurerm_lb_backend_address_pool.main.id
}
