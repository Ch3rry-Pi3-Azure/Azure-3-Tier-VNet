output "nat_gateway_id" {
  value = azurerm_nat_gateway.main.id
}

output "nat_gateway_name" {
  value = azurerm_nat_gateway.main.name
}

output "nat_public_ip_id" {
  value = azurerm_public_ip.nat.id
}

output "nat_public_ip_address" {
  value = azurerm_public_ip.nat.ip_address
}
