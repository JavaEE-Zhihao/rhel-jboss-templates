@description('The base URI where artifacts required by this template are located. When the template is deployed using the accompanying scripts, a private location in the subscription will be used and this value will be automatically generated.')
param artifactsLocation string = deployment().properties.templateLink.uri

@description('The sasToken required to access _artifactsLocation.  When the template is deployed using the accompanying scripts, a sasToken will be automatically generated.')
@secure()
param artifactsLocationSasToken string = ''

@description('Location for all resources')
param location string = resourceGroup().location

@description('An user assigned managed identity. Make sure the identity has permission to create/update/delete/list Azure resources.')
param identity object = {}

@description('Unique name for the cluster')
param clusterName string

@description('Name for the resource group of the existing cluster')
param clusterRGName string = ''

@description('Flag indicating whether to deploy a S2I application or not')
param deployApplication bool = true

@description('URL to the repository containing the application source code.')
param srcRepoUrl string = ''

@description('Flag indicating whether to create a new cluster or not')
param createCluster bool = true

@description('The Git repository reference to use for the source code. This can be a Git branch or tag reference.')
param srcRepoRef string = ''

@description('The directory within the source repository to build.')
param srcRepoDir string = ''

@description('Red Hat Container Registry Service account username')
param conRegAccUserName string = ''

@secure()
@description('Red Hat Container Registry Service account password')
param conRegAccPwd string = ''

@description('The name of the project')
param projectName string = 'eap-demo'

@description('The name of the application')
param applicationName string = 'eap-app'

@description('The number of application replicas to deploy')
param appReplicas int = 2
param guidValue string = ''

@description('${label.tagsLabel}')
param tagsByResource object

@secure()
@description('The pull secret to use for the deployment')
param pullSecret string = ''

var const_scriptLocation = uri(artifactsLocation, 'scripts/')
var const_setupJBossScript = 'jboss-setup.sh'
var const_helmYaml = 'helm.yaml.template'
var const_redHatCatalog = 'redhat-catalog.yaml'
var const_deploymentTemplate = 'app-deployment.yaml.template'
var const_operator = 'eap-operator-sub.yaml'
var const_azcliVersion = '2.53.0'
var jbossSetup_name = 'jboss-setup-${guidValue}'

resource jbossSetup 'Microsoft.Resources/deploymentScripts@${azure.apiVersionForDeploymentScript}' = {
  name: jbossSetup_name
  location: location
  kind: 'AzureCLI'
  identity: identity
  tags: tagsByResource['${identifier.deploymentScripts}']
  properties: {
    azCliVersion: const_azcliVersion
    environmentVariables: [
      {
        name: 'CREATE_CLUSTER'
        value: createCluster
      }
      {
        name: 'RESOURCE_GROUP'
        value: clusterRGName
      }
      {
        name: 'CLUSTER_NAME'
        value: clusterName
      }
      {
        name: 'DEPLOY_APPLICATION'
        value: string(deployApplication)
      }
      {
        name: 'SRC_REPO_URL'
        value: srcRepoUrl
      }
      {
        name: 'SRC_REPO_REF'
        value: srcRepoRef
      }
      {
        name: 'SRC_REPO_DIR'
        value: srcRepoDir
      }
      {
        name: 'CON_REG_ACC_USER_NAME'
        value: conRegAccUserName
      }
      {
        name: 'CON_REG_ACC_PWD'
        value: conRegAccPwd
      }
      {
        name: 'CON_REG_SECRET_NAME'
        value: replace(conRegAccUserName, '|', '-')
      }
      {
        name: 'PROJECT_NAME'
        value: projectName
      }
      {
        name: 'APPLICATION_NAME'
        value: applicationName
      }
      {
        name: 'APP_REPLICAS'
        value: string(appReplicas)
      }
      {
        name: 'PULL_SECRET'
        value: base64(pullSecret)
      }
    ]
    primaryScriptUri: uri(const_scriptLocation, '${const_setupJBossScript}${artifactsLocationSasToken}')
    supportingScriptUris: [
      uri(const_scriptLocation, '${const_helmYaml}${artifactsLocationSasToken}')
      uri(const_scriptLocation, '${const_redHatCatalog}${artifactsLocationSasToken}')
      uri(const_scriptLocation, '${const_deploymentTemplate}${artifactsLocationSasToken}')
      uri(const_scriptLocation, '${const_operator}${artifactsLocationSasToken}')
    ]
    cleanupPreference:'OnSuccess'
    retentionInterval: 'P1D'
  }
}

output consoleUrl string = jbossSetup.properties.outputs.consoleUrl
output appEndpoint string = deployApplication ? jbossSetup.properties.outputs.appEndpoint : ''
