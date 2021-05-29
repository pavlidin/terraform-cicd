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
  name     = "cicd-resources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "cicd" {
  name                = "cicd-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicd.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "cicd" {
  name                = "cicd-publicIP"
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
# Network Security Groups control the flow of network traffic in and out of your VM.
resource "azurerm_network_security_group" "cicd" {
  name                = "cicdSG"
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name
  security_rule {
    name                       = "troll"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "cicd" {
  name                = "cicd-nic"
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "cicd" {
  name                  = "cicd-vm"
  location              = azurerm_resource_group.cicd.location
  resource_group_name   = azurerm_resource_group.cicd.name
  network_interface_ids = [azurerm_network_interface.cicd.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}