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
  description = "Resource group name for the VM."
}

variable "location" {
  type        = string
  description = "Azure region for the VM."
  default     = "eastus2"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the web VM."
}

variable "lb_backend_pool_id" {
  type        = string
  description = "Load balancer backend pool ID."
}

variable "vm_name" {
  type        = string
  description = "Explicit VM name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "vm_name_prefix" {
  type        = string
  description = "Prefix used to build the VM name when vm_name is null."
  default     = "vm-web"
}

variable "nic_name_prefix" {
  type        = string
  description = "Prefix used to build the NIC name."
  default     = "nic-web"
}

variable "vm_size" {
  type        = string
  description = "Azure VM size."
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "admin_password" {
  type        = string
  description = "Admin password for the VM."
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the VM resources."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

variable "app_tier_url" {
  type        = string
  description = "Optional app tier base URL for the web UI to query."
  default     = null
}

resource "random_pet" "vm" {
  length    = 2
  separator = "-"
}

locals {
  vm_name       = var.vm_name != null ? var.vm_name : "${var.vm_name_prefix}-${random_pet.vm.id}"
  nic_name      = "${var.nic_name_prefix}-${random_pet.vm.id}"
  computer_name = substr("vm${replace(random_pet.vm.id, "-", "")}", 0, 15)
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
  backend_address_pool_id = var.lb_backend_pool_id
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
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    app_tier_url = var.app_tier_url != null ? var.app_tier_url : ""
  }))
  tags                            = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-${random_pet.vm.id}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
