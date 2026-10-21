targetScope = 'resourceGroup'

param location string = resourceGroup().location
param prefix string = 'retailandes'
@secure()
param demoSecretValue string
@description('false = solo infraestructura base. true = tambien crea el App Service.')
param deployWebApp bool = false
@description('Nombre:tag de la imagen dentro de ACR')
param image string = 'retail-app:v1'
@description('SKU del plan de App Service. Si B1 falla por cuota, probar F1.')
param webSku string = 'B1'
param tags object = {
  project: 'bootcamp-azure'
  env: 'dev'
  owner: 'estudiante'
}

var suffix = uniqueString(resourceGroup().id)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var kvSecretsUserRoleId = '4633458b-17de-408f-b874-0f0ed2e5a4fc'
var blobReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84da7d'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-appi'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-id'
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: '${prefix}acr${suffix}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
  }
}

resource demoSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'demo-secret'
  properties: { value: demoSecretValue }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource docsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'documentos'
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${prefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.0.0.0/16' ] }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

resource kvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, identity.id, kvSecretsUserRoleId)
  scope: kv
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
  }
}

resource blobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identity.id, blobReaderRoleId)
  scope: storage
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobReaderRoleId)
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = if (deployWebApp) {
  name: '${prefix}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: { name: webSku }
  properties: { reserved: true }
}

resource web 'Microsoft.Web/sites@2023-12-01' = if (deployWebApp) {
  name: '${prefix}-web-${suffix}'
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  dependsOn: [ acrPull, kvAccess ]
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/${image}'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: identity.properties.clientId
      appSettings: [
        { name: 'WEBSITES_PORT', value: '80' }
        { name: 'KEY_VAULT_URL', value: kv.properties.vaultUri }
        { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
      ]
    }
  }
}

output acrName string = acr.name
output keyVaultName string = kv.name
output storageName string = storage.name
output webUrl string = deployWebApp ? 'https://${web!.properties.defaultHostName}' : ''
