output "virtual_network_id" {
  value = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  value = azurerm_virtual_network.main.name
}

output "vnet_name_suffix" {
  value = random_pet.vnet.id
}
