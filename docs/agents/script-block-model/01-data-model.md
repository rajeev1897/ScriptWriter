# Agent 01 — Data Model

## Role

Salesforce metadata agent. Create the scene/block data model only. No Apex/LWC behavior changes except permissions/manifest needed to deploy objects.

## Branch

1. If not already on it: create/switch to `feature/script-block-model` from latest `main`.
2. Do all work on that branch.

## Build

### `Script_Scene__c` (Master-Detail to `Script__c`)

| Field | Type | Notes |
|-------|------|-------|
| `Script__c` | Master-Detail → Script__c | Required |
| `Sequence__c` | Number(8,0) | Required, scene order |
| `Scene_Heading__c` | Text(255) | e.g. INT. OFFICE - DAY |
| `Location__c` | Text(255) | Optional |
| `Time_Of_Day__c` | Text(80) | Optional |
| `Summary__c` | Long Text Area (32768) | Optional |

Name field: AutoNumber `SCN-{000000}` or Text title — prefer AutoNumber.

### `Script_Block__c` (Master-Detail to Script + Scene)

| Field | Type | Notes |
|-------|------|-------|
| `Script__c` | Master-Detail → Script__c | Required |
| `Script_Scene__c` | Master-Detail → Script_Scene__c | Required |
| `Sequence__c` | Number(8,0) | Required, order within scene |
| `Block_Type__c` | Picklist | Scene Heading, Action, Character, Dialogue, Parenthetical, Transition |
| `Text__c` | Long Text Area (131072) | Paragraph body |
| `Format_Metadata__c` | Long Text Area (32768) | Optional JSON |

Name field: AutoNumber `BLK-{000000}`.

### Keep existing

- Do **not** delete `Script_Document__c` or File fields.
- Add `Script_Version__c.Version_Label__c` (Text 80, optional) if missing.

### Also update

- Tabs for Scene/Block (optional but preferred)
- `Script_Studio_User` permission set: object + field access
- `Script_Studio` app: add tabs if created
- `manifest/package.xml`
- Basic layouts for Scene/Block

## Do not

- Change LWC or Apex save/load logic
- Migrate data
- Touch unrelated Community/login classes

## Acceptance

- Metadata validates/deploys to `personalDev`
- Objects visible with permission set
- Block types match editor types (map labels ↔ LWC values in a comment in README or field descriptions)

## End of agent

1. Deploy: `sf project deploy start --manifest manifest/package.xml --target-org personalDev` (or metadata-only path for new objects)
2. Commit on `feature/script-block-model` with message like: `Add Script Scene and Block data model.`
3. Do **not** push unless the user asks
4. Stop and report files changed + deploy result
