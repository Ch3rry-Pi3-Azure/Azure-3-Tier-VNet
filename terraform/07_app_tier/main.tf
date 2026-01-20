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

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the app tier."
}

variable "location" {
  type        = string
  description = "Azure region for the app tier."
  default     = "eastus2"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the app tier."
}

variable "app_port" {
  type        = number
  description = "Port used by the app service and internal load balancer."
  default     = 8080
}

variable "probe_path" {
  type        = string
  description = "HTTP path for the app tier health probe."
  default     = "/health"
}

variable "lb_name" {
  type        = string
  description = "Explicit internal load balancer name. When null, a random suffix is added to the prefix."
  default     = null
}

variable "lb_name_prefix" {
  type        = string
  description = "Prefix used to build the internal load balancer name when lb_name is null."
  default     = "lb-app"
}

variable "lb_sku" {
  type        = string
  description = "SKU for the internal load balancer."
  default     = "Standard"
}

variable "vm_name" {
  type        = string
  description = "Explicit VM name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "vm_name_prefix" {
  type        = string
  description = "Prefix used to build the VM name when vm_name is null."
  default     = "vm-app"
}

variable "nic_name_prefix" {
  type        = string
  description = "Prefix used to build the NIC name."
  default     = "nic-app"
}

variable "vm_size" {
  type        = string
  description = "Azure VM size for the app tier."
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the app VM."
  default     = "azureuser"
}

variable "admin_password" {
  type        = string
  description = "Admin password for the app VM."
  sensitive   = true
}

variable "sql_server_fqdn" {
  type        = string
  description = "SQL server FQDN for the app tier."
  default     = null
}

variable "sql_database_name" {
  type        = string
  description = "SQL database name for the app tier."
  default     = null
}

variable "sql_admin_login" {
  type        = string
  description = "SQL admin login for the app tier."
  default     = null
}

variable "sql_admin_password" {
  type        = string
  description = "SQL admin password for the app tier."
  sensitive   = true
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the app tier resources."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "app" {
  length    = 2
  separator = "-"
}

locals {
  lb_name           = var.lb_name != null ? var.lb_name : "${var.lb_name_prefix}-${random_pet.app.id}"
  frontend_name     = "fe-${random_pet.app.id}"
  backend_pool_name = "be-${random_pet.app.id}"
  probe_name        = "probe-${random_pet.app.id}"
  rule_name         = "app-${random_pet.app.id}"
  vm_name           = var.vm_name != null ? var.vm_name : "${var.vm_name_prefix}-${random_pet.app.id}"
  nic_name          = "${var.nic_name_prefix}-${random_pet.app.id}"
  computer_name     = substr("app${replace(random_pet.app.id, "-", "")}", 0, 15)
}

resource "azurerm_lb" "internal" {
  name                = local.lb_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.lb_sku
  tags                = var.tags

  frontend_ip_configuration {
    name                          = local.frontend_name
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "main" {
  name            = local.backend_pool_name
  loadbalancer_id = azurerm_lb.internal.id
}

resource "azurerm_lb_probe" "main" {
  name            = local.probe_name
  loadbalancer_id = azurerm_lb.internal.id
  protocol        = "Http"
  port            = var.app_port
  request_path    = var.probe_path
}

resource "azurerm_lb_rule" "main" {
  name                           = local.rule_name
  loadbalancer_id                = azurerm_lb.internal.id
  protocol                       = "Tcp"
  frontend_port                  = var.app_port
  backend_port                   = var.app_port
  frontend_ip_configuration_name = local.frontend_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
}

resource "azurerm_network_interface" "main" {
  name                = local.nic_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "main" {
  network_interface_id    = azurerm_network_interface.main.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = local.vm_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.main.id]
  computer_name                   = local.computer_name
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    app_port           = var.app_port
    sql_server_fqdn    = var.sql_server_fqdn != null ? var.sql_server_fqdn : ""
    sql_database_name  = var.sql_database_name != null ? var.sql_database_name : ""
    sql_admin_login    = var.sql_admin_login != null ? var.sql_admin_login : ""
    sql_admin_password = var.sql_admin_password != null ? var.sql_admin_password : ""
  }))
  tags                            = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-${random_pet.app.id}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
