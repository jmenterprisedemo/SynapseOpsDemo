// ************** Parameters *******************

param name string

param sqlAdministratorLogin string = 'sqladminuser'

@secure()
param sqlAdministratorLoginPassword string

@description('Object ID for the Active Directory user or group that will be granted access to this resource')
param userObjectId string

@description('When true adds a firewall rule to open access to any IP address, use only for testing')
param allowAllConnections bool = true

@allowed([
  'default'
  ''
])
param managedVirtualNetwork string = 'default'

@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Use this field if you need to have a specific Resource Group name for the automatically created RG where all the resources are stored.')
param managedResourceGroupName string = ''

param location string = resourceGroup().location


@description('The SKU name. Required for account creation; optional for update. Note that in older versions, SKU name was called accountType.')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_LRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Standard_ZRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Set the minimum TLS version to be permitted on requests to storage. The default interpretation is TLS 1.2 for this property.')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

// ************** Variables *******************

var uniqueName = substring('${name}${uniqueString(resourceGroup().id)}',0,19)
var storageName = '${uniqueName}stg'
var filesystemName = '${name}fs'
var storageBlobDataContributorRoleID = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageRoleUniqueId =  guid(resourceId('Microsoft.Storage/storageAccounts', name), storageName)
var storageRoleUserUniqueId = guid(resourceId('Microsoft.Storage/storageAccounts', name), userObjectId)
var datalakeUrl = 'https://${storageName}.dfs.${environment().suffixes.storage}'
var storageKind = 'StorageV2'

// *********** Resources ***********

// Data Lake Store
resource datalake 'Microsoft.Storage/storageAccounts@2021-01-01' = {
  name: storageName
  location: location
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: true
    minimumTlsVersion: minimumTlsVersion
  }
  sku: {
    name: storageAccountType
  }
  kind: storageKind
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2021-02-01' = {
  name:  '${storageName}/default'
  dependsOn:[
    datalake
  ]
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-01-01' = {
  name: '${storageName}/default/${filesystemName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    blob
  ]
}


// ************* Synapse workspace *************

resource synapse 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: datalakeUrl
      filesystem: filesystemName
    }
    managedVirtualNetwork: managedVirtualNetwork
    managedResourceGroupName: managedResourceGroupName
    publicNetworkAccess: publicNetworkAccess
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
  }
  dependsOn: [
    datalake
    container
  ]
}

resource synapse_allowAzure 'Microsoft.Synapse/workspaces/firewallrules@2021-06-01' = {
  parent: synapse
  // DO NOT CHANGE NAME OR IP ADDRESSES
  // If you want to add this rule, the name should be explicitely this one
  name: 'AllowAllWindowsAzureIps' 
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource synapse_allowAll 'Microsoft.Synapse/workspaces/firewallrules@2021-06-01' = if (allowAllConnections) {
  parent: synapse
  name: 'allowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

//example https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.synapse/synapse-poc/azuredeploy.json

resource synapse_grant 'Microsoft.Synapse/workspaces/managedIdentitySqlControlSettings@2021-06-01' = {
  parent: synapse
  name: 'default'
  properties: {
    grantSqlControlToManagedIdentity: {
      desiredState: 'Enabled'
    }
  }
}

// TODO Add workspace role assignments

// Role Assignments
resource synapseroleassing 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: storageRoleUniqueId
  scope: datalake
  properties:{
    principalId: synapse.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleID)
  }
}

resource userroleassing 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: storageRoleUserUniqueId
  scope: datalake
  properties:{
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleID)
  }
}


// ******** Output ********
output workspaceLink string = reference('Microsoft.Synapse/workspaces/${name}', '2021-06-01', 'Full').properties.connectivityEndpoints['web']
