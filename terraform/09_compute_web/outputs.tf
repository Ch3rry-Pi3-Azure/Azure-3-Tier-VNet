output "vm_id" {
  value = azurerm_linux_virtual_machine.main.id
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.main.name
}

output "nic_id" {
  value = azurerm_network_interface.main.id
}

output "private_ip_address" {
  value = azurerm_network_interface.main.private_ip_address
}
