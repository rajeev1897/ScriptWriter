# PersonalDev — Script Studio

Salesforce DX project for Script Studio (screenplay / synopsis editor).

## Script text source of truth

- **Working content:** `Script_Scene__c` and `Script_Block__c` (read and write).
- **Version snapshots:** `Script_Version__c` points at a `ContentVersion` JSON file (manual save, import, export).
- **Legacy:** Older `Script_Document__c` File/Long Text bodies migrate into scenes/blocks on first open; the document row is marked `Migrated` and kept as backup.

See [docs/agents/script-block-model/README.md](docs/agents/script-block-model/README.md) for the full scene/block model notes.

## Salesforce DX

- Configure the project via `sfdx-project.json` ([Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm)).
- Org alias used for this work: `personalDev`.
- Feature branch for the block model: `feature/script-block-model`.
