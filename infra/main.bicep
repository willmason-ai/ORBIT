// ============================================================
// ORBIT — main.bicep
// Operations Reporting & Brief Intelligence Tracker
//
// Deploy to: rg-orbit-wmason (Central US)
// Cross-RG refs: rg-avs2 (VNet, SQL, LAW)
//
//   az deployment group create -g rg-orbit-wmason \
//     -f infra/main.bicep -p @infra/parameters.json
// ============================================================

targetScope = 'resourceGroup'

// ----- Core parameters -----
@description('Azure region — must match rg-avs2 VNet.')
param location string = 'centralus'

@description('Entra ID tenant GUID (presidiorocks.com).')
param tenantId string = subscription().tenantId

@description('Object ID of the deployer. Gets Key Vault Administrator on the new KV.')
param deployerObjectId string

@description('Comma-separated supervisor emails for the notifier.')
param supervisorEmails string = 'will@presidiorocks.com'

// ----- Cross-RG references (rg-avs2) -----
@description('Resource group holding the shared VNet, SQL server, and LAW.')
param networkRgName string = 'rg-avs2'

@description('Existing VNet name in networkRgName.')
param vnetName string = 'Vnet-Workload-01'

@description('Subnet delegated to Microsoft.Web/serverFarms (Function + App Service VNet integration).')
param functionSubnetName string = 'snet-avs-function'

@description('Existing SQL server name in networkRgName (public access disabled — Function reaches it via VNet + PE).')
param existingSqlServerName string = 'sql-avsnetmon'

@description('Existing Log Analytics workspace name in networkRgName.')
param existingLawName string = 'law-shane'

// ----- SQL database params -----
@description('Database name to create on the existing SQL server.')
param sqlDatabaseName string = 'orbitdb'

// ----- Naming -----
var storageAccountName   = 'storbitwmason'
var containerName        = 'orbit-pptx-raw'
var docIntName           = 'docint-orbit-wmason'
var keyVaultName         = 'kv-orbit-wmason'
var appInsightsName      = 'appi-orbit-wmason'
var functionAppName      = 'func-orbit-wmason'
var functionPlanName     = 'flex-orbit-wmason'
var appServicePlanName   = 'asp-orbit-linux-wmason'
var dashboardAppName     = 'app-orbit-dashboard-wmason'
var ingestorLogicAppName = 'logic-orbit-ingestor-wmason'
var notifierLogicAppName = 'logic-orbit-notifier-wmason'

// ============================================================
// EXISTING RESOURCE REFERENCES (rg-avs2)
// ============================================================
resource functionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  scope: resourceGroup(networkRgName)
  name: '${vnetName}/${functionSubnetName}'
}

resource existingLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  scope: resourceGroup(networkRgName)
  name: existingLawName
}

resource existingSqlServer 'Microsoft.Sql/servers@2023-08-01-preview' existing = {
  scope: resourceGroup(networkRgName)
  name: existingSqlServerName
}

// ============================================================
// MODULE: Create orbitdb on existing SQL server in rg-avs2
// ============================================================
module orbitDatabase 'modules/orbitdb.bicep' = {
  scope: resourceGroup(networkRgName)
  name: 'deploy-orbitdb'
  params: {
    sqlServerName: existingSqlServerName
    databaseName: sqlDatabaseName
    location: location
  }
}

// ============================================================
// STORAGE — ORBIT-specific, with lifecycle policy
// ============================================================
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
  }
}

resource pptxContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: { publicAccess: 'None' }
}

resource appPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'app-package'
  properties: { publicAccess: 'None' }
}

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'orbit-archive-after-2-years'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [ 'blockBlob' ]
              prefixMatch: [ '${containerName}/' ]
            }
            actions: {
              baseBlob: {
                tierToArchive: { daysAfterModificationGreaterThan: 730 }
              }
            }
          }
        }
      ]
    }
  }
}

// ============================================================
// AZURE AI DOCUMENT INTELLIGENCE (S0)
// ============================================================
resource docInt 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: docIntName
  location: location
  kind: 'FormRecognizer'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: docIntName
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================
// KEY VAULT — ORBIT-specific, RBAC-only
// ============================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// Placeholder secrets — load real values post-deploy
resource kvAnthropic 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ANTHROPIC-API-KEY'
  properties: { value: 'REPLACE_ME' }
}

resource kvSqlConn 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SQL-CONNECTION-STRING'
  properties: {
    value: 'Driver={ODBC Driver 18 for SQL Server};Server=tcp:${existingSqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};Uid=REPLACE_ME;Pwd=REPLACE_ME;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;'
  }
}

resource kvDocintEndpoint 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DOCINT-ENDPOINT'
  properties: { value: docInt.properties.endpoint }
}

resource kvDocintKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DOCINT-KEY'
  properties: { value: docInt.listKeys().key1 }
}

// ============================================================
// APP INSIGHTS (new, linked to existing LAW in rg-avs2)
// ============================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: existingLaw.id
  }
}

// ============================================================
// FUNCTION APP — Flex Consumption, Python 3.12
// VNet-integrated into snet-avs-function (reaches SQL via PE)
// ============================================================
resource functionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: functionPlanName
  location: location
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  kind: 'functionapp'
  properties: { reserved: true }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnet.id
    vnetRouteAllEnabled: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}app-package'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 10
        instanceMemoryMB: 2048
      }
      runtime: { name: 'python', version: '3.12' }
    }
    siteConfig: {
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'AzureWebJobsStorage__accountName',      value: storage.name }
        { name: 'ANTHROPIC_API_KEY',                     value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=ANTHROPIC-API-KEY)' }
        { name: 'SQL_CONNECTION_STRING',                 value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=SQL-CONNECTION-STRING)' }
        { name: 'DOCINT_ENDPOINT',                       value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=DOCINT-ENDPOINT)' }
        { name: 'DOCINT_KEY',                            value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=DOCINT-KEY)' }
        { name: 'BLOB_CONTAINER_NAME',                   value: containerName }
        { name: 'STORAGE_ACCOUNT_NAME',                  value: storage.name }
        { name: 'PARSE_CONFIDENCE_THRESHOLD',            value: '0.70' }
        { name: 'PROJECT_MATCH_THRESHOLD',               value: '0.85' }
        { name: 'SUPERVISOR_EMAILS',                     value: supervisorEmails }
        { name: 'ORBIT_ENV',                             value: 'production' }
        { name: 'ORBIT_TENANT_ID',                       value: tenantId }
      ]
    }
  }
}

// ============================================================
// DASHBOARD — App Service Plan B1 + App Service (Node 20)
// VNet-integrated into the same subnet
// ============================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: { name: 'B1', tier: 'Basic' }
  kind: 'linux'
  properties: { reserved: true }
}

resource dashboardApp 'Microsoft.Web/sites@2023-12-01' = {
  name: dashboardAppName
  location: location
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnet.id
    vnetRouteAllEnabled: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      appSettings: [
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT',      value: 'true' }
        { name: 'VITE_API_BASE_URL',                   value: 'https://${functionApp.properties.defaultHostName}' }
        { name: 'VITE_TENANT_ID',                      value: tenantId }
      ]
    }
  }
}

// ============================================================
// LOGIC APPS (Consumption) — shells for workflow upload
// ============================================================
resource ingestorLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: ingestorLogicAppName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {}
      actions: {}
      outputs: {}
    }
  }
}

resource notifierLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: notifierLogicAppName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {}
      actions: {}
      outputs: {}
    }
  }
}

// ============================================================
// ROLE ASSIGNMENTS
// ============================================================
var storageBlobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var keyVaultSecretsUserRoleId    = '4633458b-17de-4a39-8594-1c93e5b6f2e8'

// Function App MI → Storage Blob Data Contributor
resource funcMiBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionApp.id, storageBlobContributorRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Function App MI → Key Vault Secrets User
resource funcMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Ingestor Logic App MI → Storage Blob Data Contributor
resource ingestorMiBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, ingestorLogicApp.id, storageBlobContributorRoleId)
  properties: {
    principalId: ingestorLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Ingestor Logic App MI → Key Vault Secrets User
resource ingestorMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, ingestorLogicApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: ingestorLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Notifier Logic App MI → Key Vault Secrets User
resource notifierMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, notifierLogicApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: notifierLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Deployer → Key Vault Administrator
resource deployerKvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, deployerObjectId, 'kvadmin')
  properties: {
    principalId: deployerObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalType: 'ServicePrincipal'
  }
}

// ============================================================
// OUTPUTS
// ============================================================
output functionAppName          string = functionApp.name
output functionAppHost          string = functionApp.properties.defaultHostName
output dashboardAppName         string = dashboardApp.name
output dashboardHost            string = dashboardApp.properties.defaultHostName
output storageAccountName       string = storage.name
output keyVaultName             string = keyVault.name
output docIntelligenceEndpoint  string = docInt.properties.endpoint
output sqlServerFqdn            string = existingSqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName          string = sqlDatabaseName
output appInsightsConnectionStr string = appInsights.properties.ConnectionString
output ingestorLogicAppName     string = ingestorLogicApp.name
output notifierLogicAppName     string = notifierLogicApp.name
