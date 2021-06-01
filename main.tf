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

resource "azurerm_resource_group" "cicd" {
  name     = "CICD"
  location = var.location

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_virtual_network" "cicdnetwork" {
  name                = "${var.prefix}-Vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.cicd.name

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_subnet" "cicdsubnet" {
  name                 = "${var.prefix}-Subnet"
  resource_group_name  = azurerm_resource_group.cicd.name
  virtual_network_name = azurerm_virtual_network.cicdnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "cicdpublicip" {
  name                = "${var.prefix}-PublicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.cicd.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_network_security_group" "cicdnsg" {
  name                = "${var.prefix}-NetworkSecurityGroup"
  location            = var.location
  resource_group_name = azurerm_resource_group.cicd.name

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
  security_rule {
    name                       = "HTTP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_network_interface" "cicdnic" {
  name                = "${var.prefix}-NIC"
  location            = var.location
  resource_group_name = azurerm_resource_group.cicd.name

  ip_configuration {
    name                          = "${var.prefix}-NicConfiguration"
    subnet_id                     = azurerm_subnet.cicdsubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cicdpublicip.id
  }

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_network_interface_security_group_association" "cicdsga" {
  network_interface_id      = azurerm_network_interface.cicdnic.id
  network_security_group_id = azurerm_network_security_group.cicdnsg.id
}

resource "random_id" "randomId" {
  keepers = {
    resource_group = azurerm_resource_group.cicd.name
  }
  byte_length = 8
}

resource "azurerm_storage_account" "cicdstorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.cicd.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "CICD Infrastructure"
  }
}

resource "azurerm_linux_virtual_machine" "cicdvm" {
  name                  = "${var.prefix}-VM"
  location              = var.location
  resource_group_name   = azurerm_resource_group.cicd.name
  network_interface_ids = [azurerm_network_interface.cicdnic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
  }

  computer_name                   = "${var.prefix}-VM"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.public_key
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.cicdstorageaccount.primary_blob_endpoint
  }

  tags = {
    environment = "CICD Infrastructure"
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "azureuser"
      private_key = var.private_key
      timeout = "2m"
      host = self.public_ip_address
    }
    inline = [
      "sudo mkdir HelloWorld",
      "sudo yum -y check-update",
      "sudo yum -y update",

      # Install and start Jenkins LTS
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key",
      "sudo yum -y upgrade",
      "sudo yum -y install jenkins java-11-openjdk-devel",
      "sudo systemctl daemon-reload",
      "sudo systemctl start jenkins",
      "sudo systemctl enable jenkins",
      # cat /var/lib/jenkins/secrets/initialAdminPassword

      # Install Ansible
      "sudo yum install -y epel-release",
      "sudo yum install -y ansible",

      # Install and start Docker
      "sudo yum install -y yum-utils",
      "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo",
      "sudo yum install -y docker-ce docker-ce-cli containerd.io",
      "sudo systemctl start docker",
      "sudo systemctl enable docker.service",
      "sudo systemctl enable containerd.service"
    ]
  }
}

# resource "azurerm_ssh_public_key" "SSHteam3Key" {
#   name                = "SSHteam3Key"
#   resource_group_name = azurerm_resource_group.cicd.name
#   location            = var.location
#   public_key          = var.public_key
# }

data "azurerm_public_ip" "cicd" {
  name                = azurerm_public_ip.cicdpublicip.name
  resource_group_name = azurerm_linux_virtual_machine.cicdvm.resource_group_name
  depends_on          = [azurerm_linux_virtual_machine.cicdvm]
}