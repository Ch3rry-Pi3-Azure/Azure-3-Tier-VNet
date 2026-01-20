output "subnet_ids_by_key" {
  value = { for key, subnet in azurerm_subnet.main : key => subnet.id }
}

output "subnet_names_by_key" {
  value = { for key, subnet in azurerm_subnet.main : key => subnet.name }
}
