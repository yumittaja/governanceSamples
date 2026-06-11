# Tag Governance Policies (Bicep)

Azure Policy templates that **mandate tags on resource groups**, **propagate those tags to the resources** within each resource group, and optionally **validate allowed values**. Designed for an environment with **multiple subscriptions** under a management group.

## What it does

| Policy | Effect | Behavior |
|--------|--------|----------|
| `require-tag-on-resource-group` | `Deny` (configurable) | Blocks creating or updating a resource group that is missing a mandated tag (e.g. `owner`). |
| `inherit-tag-from-resource-group` | `modify` | When a resource is created or updated and its parent resource group has a non-empty value for the tag, the resource gets the same tag/value. |
| `allowed-tag-values` | `Audit` (configurable) | Flags resources/resource groups whose tag value is not in the allowed list (only when the tag is present). |

Each policy definition is **reusable** (parameterized by tag name) and referenced once per governed tag. They are grouped into a single **initiative** (`tag-governance-initiative`) and assigned once at the **management group**, so the rules apply to all current and future child subscriptions automatically.

## Files

| File | Scope | Purpose |
|------|-------|---------|
| `main.bicep` | `managementGroup` | Tag list, initiative, assignment (with managed identity), and role assignment. |
| `modules/policy-definitions.bicep` | `managementGroup` | The three reusable custom policy definitions. |
| `main.bicepparam` | — | Parameter values (the governed tag list). |

## Parameters

| Name | Default | Description |
|------|---------|-------------|
| `tags` | see below | List of governed tags and how each is enforced. |
| `location` | `deployment().location` | Region for the assignment's managed identity. |
| `requireTagEffect` | `Deny` | Effect of the require-tag policies: `Deny`, `Audit`, or `Disabled`. |
| `allowedValuesEffect` | `Audit` | Effect of the allowed-values policies: `Audit`, `Deny`, or `Disabled`. |

Each entry in `tags` has the shape:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Tag name, e.g. `owner`, `costcenter`. CAF recommends lowercase keys. |
| `mandateOnResourceGroup` | bool | Require the tag on resource groups. |
| `inheritToResources` | bool | Propagate the RG tag value onto resources. |
| `allowedValues` | string[] (optional) | When set, an allowed-values policy validates the tag. |

Default governed tags (FinOps + governance aligned):

| Tag | Mandate on RG | Inherit | Allowed values |
|-----|:---:|:---:|----------------|
| `owner` | ✔ | ✔ | — |
| `costcenter` | ✔ | ✔ | — |
| `environment` | ✔ | ✔ | `prod`, `staging`, `test`, `dev` |
| `businessunit` | — | ✔ | — |
| `application` | — | ✔ | — |
| `dataclassification` | — | — | `public`, `internal`, `confidential`, `restricted` |

Edit `main.bicepparam` to change the governed tags and effects.

## Requirements

- **Bicep CLI / Azure CLI** installed.
- **Deployment scope:** a management group (use its ID below).
- **Permissions:** the deploying principal needs `Owner`, **or** `Resource Policy Contributor` + `User Access Administrator`, at the management group — the template creates a role assignment.
- **Managed identity:** the assignment uses a system-assigned identity granted the **Tag Contributor** built-in role (`4a9ae827-6dc8-4573-8ac7-8239d42aa03f`) at the management group, required by the `modify` effect.

## Deploy

```powershell
az deployment mg create `
  --management-group-id <your-mg-id> `
  --location westeurope `
  --template-file main.bicep `
  --parameters main.bicepparam
```

## Remediate existing resources

Policy `deny`/`modify` only act at **create/update** time. To tag resources that already exist, run a remediation task per inherited tag after deployment (allow a few minutes for the managed identity's role assignment to propagate first). The `--definition-reference-id` is `inherit-<tagName>`:

```powershell
az policy remediation create `
  --name remediate-inherit-owner `
  --management-group <your-mg-id> `
  --policy-assignment tag-governance `
  --definition-reference-id inherit-owner
```

## Notes

- `inherit-tag-from-resource-group` uses `mode: 'Indexed'`, so it only targets resources that support tags and locations.
- `allowed-tag-values` only evaluates when the tag is present, so it complements (does not duplicate) the require policy.
- The policy-rule expressions compile to ARM as `[[concat(...)]` / `[[resourceGroup()...]`. The double bracket is intentional: ARM un-escapes it to the literal string the Policy engine evaluates at runtime.
- Tag keys are **case-sensitive** in Azure cost reports — keep naming consistent (the defaults use PascalCase).
- Adding or removing entries in `tags` re-generates the initiative references on the next deployment.
