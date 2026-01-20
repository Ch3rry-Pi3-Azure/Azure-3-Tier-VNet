output "nsg_ids_by_key" {
  value = { for key, nsg in azurerm_network_security_group.main : key => nsg.id }
}

output "nsg_names_by_key" {
  value = { for key, nsg in azurerm_network_security_group.main : key => nsg.name }
}
