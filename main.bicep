targetScope = 'managementGroup'

@description('Configuration for a tag that is governed by the initiative.')
type tagConfig = {
  @description('Tag name, e.g. "Owner" or "CostCenter".')
  name: string

  @description('Require the tag to exist on resource groups (uses the requireTagEffect).')
  mandateOnResourceGroup: bool

  @description('Inherit the tag value from the parent resource group onto resources.')
  inheritToResources: bool

  @description('Optional allowed values. When set, an audit policy flags values outside this list.')
  allowedValues: string[]?
}

@description('Tags governed by the initiative and how each is enforced.')
param tags tagConfig[] = [
  {
    name: 'owner'
    mandateOnResourceGroup: true
    inheritToResources: true
  }
  {
    name: 'costcenter'
    mandateOnResourceGroup: true
    inheritToResources: true
  }
  {
    name: 'environment'
    mandateOnResourceGroup: true
    inheritToResources: true
    allowedValues: [
      'prod'
      'staging'
      'test'
      'dev'
    ]
  }
  {
    name: 'businessunit'
    mandateOnResourceGroup: false
    inheritToResources: true
  }
  {
    name: 'application'
    mandateOnResourceGroup: false
    inheritToResources: true
  }
  {
    name: 'dataclassification'
    mandateOnResourceGroup: false
    inheritToResources: false
    allowedValues: [
      'public'
      'internal'
      'confidential'
      'restricted'
    ]
  }
]

@description('Azure region used for the policy assignment managed identity.')
param location string = deployment().location

@description('Effect for the "require tag on resource group" policies.')
@allowed([
  'Deny'
  'Audit'
  'Disabled'
])
param requireTagEffect string = 'Deny'

@description('Effect for the "allowed tag values" policies.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param allowedValuesEffect string = 'Audit'

// Tag Contributor built-in role - granted to the assignment identity for the modify effect.
var tagContributorRoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

module policyDefinitions 'modules/policy-definitions.bicep' = {}

// Definition IDs are deterministic (fixed names at this management group), so they can be
// referenced inside for-loops. The explicit dependency on the module ensures ordering.
var requireTagPolicyId = managementGroupResourceId('Microsoft.Authorization/policyDefinitions', 'require-tag-on-resource-group')
var inheritTagPolicyId = managementGroupResourceId('Microsoft.Authorization/policyDefinitions', 'inherit-tag-from-resource-group')
var allowedTagValuesPolicyId = managementGroupResourceId('Microsoft.Authorization/policyDefinitions', 'allowed-tag-values')

// Build the initiative's policy references by filtering the tag list per behavior.
var mandatedTags = filter(tags, t => t.mandateOnResourceGroup)
var inheritedTags = filter(tags, t => t.inheritToResources)
var valueConstrainedTags = filter(tags, t => t.?allowedValues != null)

var requireRefs = [
  for t in mandatedTags: {
    policyDefinitionReferenceId: 'require-${t.name}'
    policyDefinitionId: requireTagPolicyId
    parameters: {
      tagName: {
        value: t.name
      }
      effect: {
        value: requireTagEffect
      }
    }
  }
]

var inheritRefs = [
  for t in inheritedTags: {
    policyDefinitionReferenceId: 'inherit-${t.name}'
    policyDefinitionId: inheritTagPolicyId
    parameters: {
      tagName: {
        value: t.name
      }
    }
  }
]

var allowedValueRefs = [
  for t in valueConstrainedTags: {
    policyDefinitionReferenceId: 'allowed-${t.name}'
    policyDefinitionId: allowedTagValuesPolicyId
    parameters: {
      tagName: {
        value: t.name
      }
      allowedValues: {
        value: t.?allowedValues ?? []
      }
      effect: {
        value: allowedValuesEffect
      }
    }
  }
]

// Groups all custom tag policies into a single initiative so they can be assigned together.
resource tagGovernanceInitiative 'Microsoft.Authorization/policySetDefinitions@2025-01-01' = {
  name: 'tag-governance-initiative'
  dependsOn: [
    policyDefinitions
  ]
  properties: {
    policyType: 'Custom'
    displayName: 'Tag governance - mandate, propagate and validate resource group tags'
    description: 'Requires tags on resource groups, inherits them onto resources, and validates allowed values.'
    metadata: {
      category: 'Tags'
      version: '2.0.0'
    }
    policyDefinitions: concat(requireRefs, inheritRefs, allowedValueRefs)
  }
}

// Per-policy non-compliance messages so a denied deployment explains exactly which tag is missing
// or invalid, instead of repeating the generic assignment display name.
var requireMessages = [
  for t in mandatedTags: {
    policyDefinitionReferenceId: 'require-${t.name}'
    message: 'Resource groups must have the "${t.name}" tag. Add it before creating or updating this resource group.'
  }
]

var allowedValueMessages = [
  for t in valueConstrainedTags: {
    policyDefinitionReferenceId: 'allowed-${t.name}'
    message: 'The "${t.name}" tag value is not allowed. Permitted values: ${join(t.allowedValues!, ', ')}.'
  }
]

var defaultMessage = [
  {
    message: 'This resource does not comply with the tag governance policy. Ensure all mandatory tags are present and valid.'
  }
]

// Assigns the initiative at the management group, covering every child subscription.
// A system-assigned identity is required because the inherit policy uses the "modify" effect.
resource tagGovernanceAssignment 'Microsoft.Authorization/policyAssignments@2025-01-01' = {
  name: 'tag-governance'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Tag governance - mandate and propagate resource group tags'
    policyDefinitionId: tagGovernanceInitiative.id
    nonComplianceMessages: concat(defaultMessage, requireMessages, allowedValueMessages)
  }
}

// Grants the assignment identity the Tag Contributor role at the management group scope so
// the modify effect can write tags on resources in any child subscription.
resource tagContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, tagGovernanceAssignment.id, tagContributorRoleDefinitionId)
  properties: {
    roleDefinitionId: tagContributorRoleDefinitionId
    principalId: tagGovernanceAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Resource ID of the tag governance policy assignment.')
output assignmentId string = tagGovernanceAssignment.id

@description('Principal ID of the assignment managed identity.')
output assignmentPrincipalId string = tagGovernanceAssignment.identity.principalId
