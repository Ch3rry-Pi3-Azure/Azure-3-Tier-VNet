output "app_lb_id" {
  value = azurerm_lb.internal.id
}

output "app_lb_name" {
  value = azurerm_lb.internal.name
}

output "app_lb_private_ip" {
  value = azurerm_lb.internal.frontend_ip_configuration[0].private_ip_address
}

output "app_backend_pool_id" {
  value = azurerm_lb_backend_address_pool.main.id
}

output "app_vm_id" {
  value = azurerm_linux_virtual_machine.main.id
}

output "app_vm_name" {
  value = azurerm_linux_virtual_machine.main.name
}

output "app_private_ip" {
  value = azurerm_network_interface.main.private_ip_address
}
