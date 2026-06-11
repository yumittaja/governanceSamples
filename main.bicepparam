using './main.bicep'

param tags = [
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

param requireTagEffect = 'Deny'
param allowedValuesEffect = 'Audit'
