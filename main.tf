# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "pf6-devops-team3"

    workspaces {
      name = "terraform-cicd"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "cicdgroup" {
  name     = "mycicdgroup"
  location = "West Europe"

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Create virtual network
resource "azurerm_virtual_network" "cicdnetwork" {
  name                = "myVnet"
  address_space       = ["10.0.0.0/16"]
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.cicdgroup.name

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Create subnet
resource "azurerm_subnet" "mycicdsubnet" {
  name                 = "mySubnet"
  resource_group_name  = azurerm_resource_group.cicdgroup.name
  virtual_network_name = azurerm_virtual_network.cicdnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "mycicdpublicip" {
  name                = "myPublicIP"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.cicdgroup.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "mycicdnsg" {
  name                = "myNetworkSecurityGroup"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.cicdgroup.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Create network interface
resource "azurerm_network_interface" "mycicdnic" {
  name                = "myNIC"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.cicdgroup.name

  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = azurerm_subnet.mycicdsubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mycicdpublicip.id
  }

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.mycicdnic.id
  network_security_group_id = azurerm_network_security_group.mycicdnsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.cicdgroup.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.cicdgroup.name
  location                 = "West Europe"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "CICD Infrastructure"
  }
}

# Create (and display) an SSH key
resource "tls_private_key" "cicd_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
output "tls_private_key" {
  value     = tls_private_key.cicd_ssh.private_key_pem
  sensitive = true
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "mycicdvm" {
  name                  = "myVM"
  location              = "West Europe"
  resource_group_name   = azurerm_resource_group.cicdgroup.name
  network_interface_ids = [azurerm_network_interface.mycicdnic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "cicdvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.cicd_ssh.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }

  tags = {
    environment = "CICD Infrastructure"
  }

  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo mkdir Helloworld",
  #     "sudo apt-get install python -y",
  #     "sudo apt-add-repository ppa:ansible/ansible",
  #     "sudo apt-get update",
  #     "sudo apt-get install ansible -y"
  #   ]
  # }
}

data "azurerm_public_ip" "cicd" {
  name                = azurerm_public_ip.mycicdpublicip.name
  resource_group_name = azurerm_linux_virtual_machine.mycicdvm.resource_group_name
  depends_on          = [azurerm_linux_virtual_machine.mycicdvm]
}

output "public_ip_address" {
  value = data.azurerm_public_ip.cicd.ip_address
}