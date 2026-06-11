targetScope = 'managementGroup'

// Tag Contributor built-in role - required by the "modify" effect to write tags onto resources.
var tagContributorRoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

// Reusable definition: requires a tag (chosen via the tagName policy parameter) to exist on
// every resource group. The effect is configurable per assignment/initiative reference.
resource requireTagOnResourceGroup 'Microsoft.Authorization/policyDefinitions@2025-01-01' = {
  name: 'require-tag-on-resource-group'
  properties: {
    policyType: 'Custom'
    mode: 'All'
    displayName: 'Require a tag on resource groups'
    description: 'Enforces the existence of a tag on resource groups.'
    metadata: {
      category: 'Tags'
      version: '2.0.0'
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag name'
          description: 'Name of the tag, such as "Owner".'
        }
      }
      effect: {
        type: 'String'
        metadata: {
          displayName: 'Effect'
        }
        allowedValues: [
          'Deny'
          'Audit'
          'Disabled'
        ]
        defaultValue: 'Deny'
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Resources/subscriptions/resourceGroups'
          }
          {
            field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
            exists: 'false'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Reusable definition: inherits the tag value from the parent resource group onto resources
// when the resource is created or updated and the resource group carries a non-empty value.
resource inheritTagFromResourceGroup 'Microsoft.Authorization/policyDefinitions@2025-01-01' = {
  name: 'inherit-tag-from-resource-group'
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: 'Inherit a tag from the resource group'
    description: 'Adds or replaces the specified tag and value from the parent resource group when any resource is created or updated.'
    metadata: {
      category: 'Tags'
      version: '2.0.0'
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag name'
          description: 'Name of the tag, such as "Owner".'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
            notEquals: '[resourceGroup().tags[parameters(\'tagName\')]]'
          }
          {
            value: '[resourceGroup().tags[parameters(\'tagName\')]]'
            notEquals: ''
          }
        ]
      }
      then: {
        effect: 'modify'
        details: {
          roleDefinitionIds: [
            tagContributorRoleDefinitionId
          ]
          operations: [
            {
              operation: 'addOrReplace'
              field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
              value: '[resourceGroup().tags[parameters(\'tagName\')]]'
            }
          ]
        }
      }
    }
  }
}

// Reusable definition: audits or denies tag values that are not in an allowed list. Only
// evaluated when the tag is present, so it complements (does not duplicate) the require policy.
resource allowedTagValues 'Microsoft.Authorization/policyDefinitions@2025-01-01' = {
  name: 'allowed-tag-values'
  properties: {
    policyType: 'Custom'
    mode: 'All'
    displayName: 'Allowed values for a tag'
    description: 'Audits or denies resources and resource groups whose tag value is not in the allowed list.'
    metadata: {
      category: 'Tags'
      version: '1.0.0'
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag name'
          description: 'Name of the tag, such as "Environment".'
        }
      }
      allowedValues: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed values'
          description: 'The list of values permitted for this tag.'
        }
      }
      effect: {
        type: 'String'
        metadata: {
          displayName: 'Effect'
        }
        allowedValues: [
          'Audit'
          'Deny'
          'Disabled'
        ]
        defaultValue: 'Audit'
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
            exists: 'true'
          }
          {
            not: {
              field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
              in: '[parameters(\'allowedValues\')]'
            }
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

@description('Resource ID of the policy that requires a tag on resource groups.')
output requireTagPolicyId string = requireTagOnResourceGroup.id

@description('Resource ID of the policy that inherits a tag from the resource group.')
output inheritTagPolicyId string = inheritTagFromResourceGroup.id

@description('Resource ID of the policy that audits/denies disallowed tag values.')
output allowedTagValuesPolicyId string = allowedTagValues.id

@description('Tag Contributor role definition ID used by the modify effect.')
output tagContributorRoleDefinitionId string = tagContributorRoleDefinitionId
