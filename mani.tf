terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.68.0"
    }
  }
}
provider "azurerm" {
    subscription_id = "7ba746b7-3c0c-4f04-b679-9a44c6c58cd0"
    client_id       = "0a7ca730-00b7-444f-9542-494b221ccc7a"
    client_secret   = "r~h8Q~lUrEd384Rd8f~3VDEojRz49vrRbf2ZTdib"
    tenant_id       = "da6a9ada-e440-4c42-bb4f-2fdbf2dc82dd"
    features {}
}
resource "azurerm_resource_group" "scale-set" {
    name = "scale-set"
    location = "East US"
  
}
resource "azurerm_virtual_network" "sacleset_network" {
    name = "scaleset-network"
    resource_group_name = azurerm_resource_group.scale-set.name
    location = azurerm_resource_group.scale-set.location
    address_space = ["10.0.0.0/16"] 
    depends_on = [ azurerm_resource_group.scale-set ]


}
resource "azurerm_subnet" "subnetA" {
    name = "subnetA"
    resource_group_name = azurerm_resource_group.scale-set.name
    virtual_network_name = azurerm_virtual_network.sacleset_network.name
    address_prefixes     = ["10.0.0.0/24"]
  depends_on = [
    azurerm_virtual_network.sacleset_network
  ]
  
}
resource "azurerm_public_ip" "load-ip" {
    name = "load-ip"
    location = azurerm_resource_group.scale-set.location
    resource_group_name = azurerm_resource_group.scale-set.name
    allocation_method = "Static"
    sku = "Standard"

}
resource "azurerm_lb" "app_balancer" {
    name = "app-balancer"
    location = azurerm_resource_group.scale-set.location
    resource_group_name = azurerm_resource_group.scale-set.name
    sku = "Standard"
    sku_tier = "Regional"
    frontend_ip_configuration {
      name = "frontend-ip"
      public_ip_address_id = azurerm_public_ip.load-ip.id
    }
    depends_on = [ azurerm_public_ip.load-ip ]
}
resource "azurerm_lb_backend_address_pool" "scalesetpool" {
    loadbalancer_id = azurerm_lb.app_balancer.id
    name = "scalesetpool"
    depends_on = [ azurerm_lb.app_balancer ]
  
}
resource "azurerm_lb_probe" "probeA" {
   # resource_group_name = azurerm_resource_group.scale-set.name
    loadbalancer_id =azurerm_lb.app_balancer.id
    name = "probeA"
    port = "80"
    protocol = "Tcp"
    depends_on = [ azurerm_lb.app_balancer ]
  
}
resource "azurerm_lb_rule" "RuleA" {
    #resource_group_name = azurerm_resource_group.scale-set.name
    loadbalancer_id = azurerm_lb.app_balancer.id
    name = "RuleA"
    protocol = "Tcp"
    frontend_port = 80
    backend_port = 80
    frontend_ip_configuration_name = "frontend-ip"
    probe_id = azurerm_lb_probe.probeA.id
    backend_address_pool_ids = [azurerm_lb_backend_address_pool.scalesetpool.id]
  
}

resource "azurerm_windows_virtual_machine_scale_set" "scale_set" {
  name                = "scale-set"
  resource_group_name = azurerm_resource_group.scale-set.name
  location            = azurerm_resource_group.scale-set.location
  sku                 = "Standard_D2s_v3"
  instances           = 2
  admin_password      = "16JE1a0538$12"
  admin_username      = "magantha"

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter-Server-Core"
    version   = "latest"
  }
  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "scaleset-interface"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnetA.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.scalesetpool.id]
    }
  }
  depends_on = [ azurerm_virtual_network.sacleset_network ]
}

  
resource "azurerm_storage_account" "charlie5577" {
  name = "charlie5577"
  resource_group_name = azurerm_resource_group.scale-set.name
  location = azurerm_resource_group.scale-set.location
  #access_tier = "Standard"
  account_replication_type = "LRS"
  #allow_blob_public_access= true
  account_tier = "Standard"

}
resource "azurerm_storage_container" "data" {
  name = "data"
  storage_account_name = "charlie5577"
  container_access_type = "blob"
  depends_on = [ azurerm_storage_account.charlie5577 ]
  
}
resource "azurerm_storage_blob" "IIS_Config" {
  name = "IIS_Config.ps1"
  storage_account_name = "charlie5577"
  storage_container_name = "data"
  type = "Block"
  source = "IIS_Config.ps1"
  depends_on = [azurerm_storage_container.data ]
  
}
resource "azurerm_virtual_machine_scale_set_extension" "scaleset_extension" {
  name = "scaleset-extension"
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.scale_set.id
  publisher = "Microsoft.Compute"
  type = "CustomScriptExtension"
  type_handler_version = "1.9"
  depends_on = [ azurerm_storage_blob.IIS_Config ]

  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.charlie5577.name}.blob.core.windows.net/data/IIS_Config.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
    }
SETTINGS
}
resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.scale-set.location
  resource_group_name = azurerm_resource_group.scale-set.name

# We are creating a rule to allow traffic on port 80
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnetA.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
  depends_on = [
    azurerm_network_security_group.app_nsg
  ]
}

