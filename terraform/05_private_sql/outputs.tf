output "sql_server_id" {
  value = azurerm_mssql_server.main.id
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_id" {
  value = azurerm_mssql_database.main.id
}

output "sql_database_name" {
  value = azurerm_mssql_database.main.name
}

output "private_endpoint_id" {
  value = azurerm_private_endpoint.sql.id
}

output "private_endpoint_private_ip" {
  value = azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address
}

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.sql.id
}
