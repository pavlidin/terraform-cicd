terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
  backend "remote" {
    organization = "pf6-devops-team3"
    workspaces {
      name = "terraform-application"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id = var.client_id
  client_secret = var.client_secret
  tenant_id = var.tenant_id
}


#Application VMs
# resource "azurerm_resource_group" "application" {
#   name     = "Application Resources"
#   location = "West Europe"
# }

# # Create a virtual network within the resource group
# resource "azurerm_virtual_network" "application" {
#   name                = "Application Network"
#   resource_group_name = azurerm_resource_group.application.name
#   location            = azurerm_resource_group.application.location
#   address_space       = ["10.0.0.0/16"]
# }

#CI/CD VM

resource "azurerm_resource_group" "cicd" {
  name     = "cicdresources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "cicd" {
  name                = "cicd-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name
}

resource "azurerm_subnet" "cicd" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "cicd" {
  name                = "cicd-nic"
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cicd.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "cicd" {
  name                = "cicd-machine"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = azurerm_resource_group.cicd.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.cicd.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("C:/ssh/cicd-sshkey.pem")
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

#   resource "azurerm_ssh_public_key" "cicd" {
#   name                = "cicd"
#   resource_group_name = "cicd"
#   location            = "West Europe"
#   public_key          = file("C:/ssh/cicd-sshkey.pem")
# }