// ============================================================
// ORBIT — main.bicep
// Operations Reporting & Brief Intelligence Tracker
// Target scope: resource group (deploy with `az deployment group create`)
// ============================================================

targetScope = 'resourceGroup'

@description('Short environment label used in resource names (e.g. prod, dev).')
param env string = 'prod'

@description('Azure region for all resources.')
param location string = 'eastus2'

@description('Administrator login for the Azure SQL logical server.')
param sqlAdminLogin string

@description('Administrator password for the Azure SQL logical server.')
@secure()
param sqlAdminPassword string

@description('Entra ID tenant GUID hosting the supervisor app registration (presidiorocks.com).')
param tenantId string = subscription().tenantId

@description('Object ID of the deployer / dashboard Entra admin. Used for Key Vault access policy seeding.')
param deployerObjectId string

@description('Comma-separated supervisor emails for the notifier.')
param supervisorEmails string = 'will@presidiorocks.com'

// ------------------------------------------------------------
// Naming
// ------------------------------------------------------------
var suffix               = toLower(env)
var storageAccountName   = 'storbitraw${suffix}'
var containerName        = 'orbit-pptx-raw'
var docIntName           = 'docint-orbit-${suffix}'
var sqlServerName        = 'sql-orbit-${suffix}'
var sqlDatabaseName      = 'orbitdb'
var keyVaultName         = 'kv-orbit-${suffix}'
var lawName              = 'law-orbit-${suffix}'
var appInsightsName      = 'appi-orbit-${suffix}'
var functionAppName      = 'func-orbit-${suffix}'
var functionPlanName     = 'flex-orbit-${suffix}'
var appServicePlanName   = 'asp-orbit-linux-${suffix}'
var dashboardAppName     = 'app-orbit-dashboard-${suffix}'
var ingestorLogicAppName = 'logic-orbit-ingestor-${suffix}'
var notifierLogicAppName = 'logic-orbit-notifier-${suffix}'

// ============================================================
// STORAGE — raw PPTX container with lifecycle policy
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
// AZURE AI DOCUMENT INTELLIGENCE
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
// AZURE SQL — Serverless GP_S_Gen5_1, auto-pause 60 min
// ============================================================
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlFirewallAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368  // 32 GB
    autoPauseDelay: 60
    minCapacity: json('0.5')
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

// ============================================================
// KEY VAULT + placeholder secrets
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

// Placeholder secrets — real values loaded post-deploy via `az keyvault secret set`
resource kvAnthropic 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ANTHROPIC-API-KEY'
  properties: { value: 'REPLACE_ME' }
}

resource kvSqlConn 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SQL-CONNECTION-STRING'
  properties: {
    value: 'Driver={ODBC Driver 18 for SQL Server};Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};Uid=${sqlAdminLogin};Pwd=${sqlAdminPassword};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;'
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
// LOG ANALYTICS + APP INSIGHTS
// ============================================================
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

// ============================================================
// FUNCTION APP — Flex Consumption, Python 3.12
// Hosts both orbit_parser (blob trigger) and orbit_api (HTTP/ASGI)
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
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}app-package'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
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
        { name: 'ORBIT_ENV',                             value: env }
        { name: 'ORBIT_TENANT_ID',                       value: tenantId }
      ]
    }
  }
}

// ============================================================
// DASHBOARD — App Service Plan + App Service (Linux, Node 20)
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
// LOGIC APPS (Consumption) — empty shells; workflows uploaded
// via workflow.json templates in /logic_apps
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
// ROLE ASSIGNMENTS (Managed Identity → resources)
// ============================================================
var storageBlobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var keyVaultSecretsUserRoleId    = '4633458b-17de-4a39-8594-1c93e5b6f2e8'

resource funcMiBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionApp.id, storageBlobContributorRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource funcMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource ingestorMiBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, ingestorLogicApp.id, storageBlobContributorRoleId)
  properties: {
    principalId: ingestorLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource ingestorMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, ingestorLogicApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: ingestorLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource notifierMiKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, notifierLogicApp.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: notifierLogicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource deployerKvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, deployerObjectId, 'kvadmin')
  properties: {
    principalId: deployerObjectId
    // Key Vault Administrator
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalType: 'User'
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
output sqlServerFqdn            string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName          string = sqlDatabaseName
output keyVaultName             string = keyVault.name
output docIntelligenceEndpoint  string = docInt.properties.endpoint
output ingestorLogicAppName     string = ingestorLogicApp.name
output notifierLogicAppName     string = notifierLogicApp.name
output appInsightsConnectionStr string = appInsights.properties.ConnectionString
