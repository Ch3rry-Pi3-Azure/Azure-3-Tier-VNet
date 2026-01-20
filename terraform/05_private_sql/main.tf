terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the SQL resources."
}

variable "location" {
  type        = string
  description = "Azure region for the SQL server and private endpoint."
  default     = "eastus2"
}

variable "virtual_network_id" {
  type        = string
  description = "Virtual network ID for the private DNS zone link."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the SQL private endpoint."
}

variable "sql_server_name" {
  type        = string
  description = "Explicit SQL server name. When null, a random suffix is added to the prefix."
  default     = null
}

variable "sql_server_name_prefix" {
  type        = string
  description = "Prefix used to build the SQL server name when sql_server_name is null."
  default     = "sql-vnet"
}

variable "sql_admin_login" {
  type        = string
  description = "SQL admin login."
  default     = "sqladmin"
}

variable "sql_admin_password" {
  type        = string
  description = "SQL admin password."
  sensitive   = true
}

variable "azuread_admin_login" {
  type        = string
  description = "Microsoft Entra admin login (user UPN)."
  default     = null
}

variable "azuread_admin_object_id" {
  type        = string
  description = "Microsoft Entra admin object id (defaults to current principal if null)."
  default     = null
}

variable "database_name" {
  type        = string
  description = "SQL database name."
  default     = "vnet-demo"
}

variable "database_sku_name" {
  type        = string
  description = "SQL database SKU."
  default     = "GP_S_Gen5_1"
}

variable "max_size_gb" {
  type        = number
  description = "SQL database max size in GB."
  default     = 1
}

variable "min_capacity" {
  type        = number
  description = "Minimum vCores for serverless compute."
  default     = 0.5
}

variable "auto_pause_delay_in_minutes" {
  type        = number
  description = "Auto-pause delay in minutes for serverless compute."
  default     = 60
}

variable "zone_redundant" {
  type        = bool
  description = "Whether the database is zone redundant."
  default     = false
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Whether public network access is enabled for the SQL server."
  default     = true
}

variable "allow_azure_services" {
  type        = bool
  description = "Whether to allow Azure services to access the SQL server via firewall rule."
  default     = true
}

variable "client_ip_address" {
  type        = string
  description = "Client public IP address allowed to access the SQL server (optional)."
  default     = null
}

variable "private_dns_zone_name" {
  type        = string
  description = "Private DNS zone name for Azure SQL."
  default     = "privatelink.database.windows.net"
}

variable "private_endpoint_name_prefix" {
  type        = string
  description = "Prefix used to build the private endpoint name."
  default     = "pe-sql"
}

variable "private_dns_zone_link_name_prefix" {
  type        = string
  description = "Prefix used to build the private DNS zone link name."
  default     = "link-sql"
}

variable "private_dns_zone_group_name" {
  type        = string
  description = "Name for the private DNS zone group."
  default     = "sql-dns"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the SQL resources."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "sql" {
  length    = 2
  separator = ""
}

locals {
  server_name = var.sql_server_name != null ? var.sql_server_name : substr("${var.sql_server_name_prefix}${random_pet.sql.id}", 0, 63)
  private_endpoint_name = "${var.private_endpoint_name_prefix}-${random_pet.sql.id}"
  dns_link_name         = "${var.private_dns_zone_link_name_prefix}-${random_pet.sql.id}"
  private_connection_name = "sql-${random_pet.sql.id}"
}

resource "azurerm_mssql_server" "main" {
  name                          = local.server_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  dynamic "azuread_administrator" {
    for_each = var.azuread_admin_login == null ? [] : [var.azuread_admin_login]
    content {
      login_username              = var.azuread_admin_login
      object_id                   = coalesce(var.azuread_admin_object_id, data.azurerm_client_config.current.object_id)
      tenant_id                   = data.azurerm_client_config.current.tenant_id
      azuread_authentication_only = false
    }
  }
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  count            = var.public_network_access_enabled && var.allow_azure_services ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "client_ip" {
  count            = var.public_network_access_enabled && var.client_ip_address != null ? 1 : 0
  name             = "ClientIPAddress"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}

resource "azurerm_mssql_database" "main" {
  name                        = var.database_name
  server_id                   = azurerm_mssql_server.main.id
  sku_name                    = var.database_sku_name
  max_size_gb                 = var.max_size_gb
  min_capacity                = var.min_capacity
  auto_pause_delay_in_minutes = var.auto_pause_delay_in_minutes
  zone_redundant              = var.zone_redundant
}

resource "azurerm_private_dns_zone" "sql" {
  name                = var.private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = local.dns_link_name
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  name                = local.private_endpoint_name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.private_connection_name
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = var.private_dns_zone_group_name
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}
