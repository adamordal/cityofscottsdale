resource "azurerm_marketplace_agreement" "palo_alto_agreement" {
  publisher = "paloaltonetworks"
  offer     = "vmseries-flex"
  plan      = "byol"
}

resource "azurerm_resource_group" "rg_palo-prod-westus3-001" {
  name     = "rg_connectivity-prod-westus3-001"
  location = "West US 3"
}


resource "azurerm_network_security_group" "palo_alto_nsg" {
  name                = "palo-alto-nsg-mgmt"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name

  security_rule {
    name                       = "Any-In"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "palo_alto_nsg_assoc" {
  count = 2
  network_interface_id      = azurerm_network_interface.palo_alto_mgmt[count.index].id
  network_security_group_id = azurerm_network_security_group.palo_alto_nsg.id
}

resource "azurerm_network_interface" "palo_alto_mgmt" {
  count               = 2
  name                = "palo-alto-mgmt-${count.index + 1}"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.Mgmt.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "palo_alto_untrust" {
  count               = 2
  name                = "palo-alto-outside-${count.index + 1}"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "Untrust"
    subnet_id                     = azurerm_subnet.Untrust.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }

  // Add a second IP configuration for the first Palo Alto firewall
  dynamic "ip_configuration" {
    for_each = count.index == 0 ? [1] : []
    content {
      name                          = "secondary"
      subnet_id                     = azurerm_subnet.Untrust.id
      private_ip_address_allocation = "Dynamic"
    }
  }
}

resource "azurerm_network_interface" "palo_alto_trust" {
  count               = 2
  name                = "palo-alto-inside-${count.index + 1}"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.Trust.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }

  // Add a second IP configuration for the first Palo Alto firewall
  dynamic "ip_configuration" {
    for_each = count.index == 0 ? [1] : []
    content {
      name                          = "secondary"
      subnet_id                     = azurerm_subnet.Trust.id
      private_ip_address_allocation = "Dynamic"
    }
  }
}

resource "azurerm_network_interface" "palo_alto_ha" {
  count               = 2
  name                = "palo-alto-ha-${count.index +1}"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.HA.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "palo_alto" {
  count               = 2
  name                = "palo-alto-${count.index + 1}"
  location            = azurerm_resource_group.rg_palo-prod-westus3-001.location
  resource_group_name = azurerm_resource_group.rg_palo-prod-westus3-001.name
  primary_network_interface_id = azurerm_network_interface.palo_alto_mgmt[count.index].id
  
  network_interface_ids = [
    azurerm_network_interface.palo_alto_mgmt[count.index].id, // Primary interface
    azurerm_network_interface.palo_alto_untrust[count.index].id,
    azurerm_network_interface.palo_alto_trust[count.index].id,
    azurerm_network_interface.palo_alto_ha[count.index].id
  ]

  vm_size = "Standard_DS3_v2"

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "byol"
    version   = "latest"
  }

  plan {
    publisher = "paloaltonetworks"
    product   = "vmseries-flex"
    name      = "byol"
  }

  storage_os_disk {
    name              = "osdisk-${count.index + 1}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  os_profile {
    computer_name  = "palo-alto-${count.index + 1}"
    admin_username = "azureuser"
    admin_password = "P@loAdminpass123" // Specify your admin password here
  }

  os_profile_linux_config {
    disable_password_authentication = false // Enable password authentication
  }

  #depends_on = [azurerm_marketplace_agreement.palo_alto_agreement]
  delete_os_disk_on_termination = true
}
