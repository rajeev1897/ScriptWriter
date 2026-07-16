# Script Block Model — Sequential Agents

Run these **one at a time**. After each agent finishes:

1. Review the diff
2. Deploy to Salesforce (`personalDev`)
3. Commit on branch `feature/script-block-model` (create it in Agent 01 if missing)
4. Reply in chat: `done, next` to start the next agent

## Branch

Use: `feature/script-block-model`

## Agents (in order)

| # | File | What it builds | Deploy after? |
|---|------|----------------|---------------|
| 01 | [01-data-model.md](01-data-model.md) | `Script_Scene__c`, `Script_Block__c`, fields, permissions, tabs | Yes |
| 02 | [02-apex-persistence.md](02-apex-persistence.md) | Scene/block Apex services + controller save/load | Yes |
| 03 | [03-lwc-dirty-autosave.md](03-lwc-dirty-autosave.md) | LWC dirty-block tracking + 5s partial autosave | Yes |
| 04 | [04-version-import-export.md](04-version-import-export.md) | Manual version snapshots + txt/PDF aligned to blocks | Yes |
| 05 | [05-migration-tests.md](05-migration-tests.md) | Legacy→blocks migration, tests, cleanup | Yes |

## How to start an agent

Paste the full contents of the phase file into a **new Agent chat**, or say:

> Run agent phase `01` from `@docs/agents/script-block-model/01-data-model.md`

Do **not** start phase N+1 until phase N is deployed and committed.

## Target architecture (locked)

```
Script__c
  ├─ Script_Scene__c (MD, Sequence__c, Scene_Heading__c, Location, Time, Summary)
  ├─ Script_Block__c (MD Script + MD Scene, Sequence__c, Block_Type__c, Text__c)
  └─ Script_Version__c (metadata only + Content_Version_Id__c → ContentVersion snapshot)
```

- Autosave: update **dirty** `Script_Block__c` rows only; bump `Script__c.Last_Saved_At__c`; no version.
- Manual save / Cmd+S: build JSON snapshot → `ContentVersion` → `Script_Version__c` pointer.
- Keep existing File-backed `Script_Document__c` readable until Agent 05 migrates.

### Block_Type__c ↔ LWC `SCREENPLAY_TYPES`

| Picklist API value (`Block_Type__c`) | Label | LWC `type` value |
|--------------------------------------|-------|------------------|
| `scene-heading` | Scene Heading | `scene-heading` |
| `action` | Action | `action` |
| `character` | Character | `character` |
| `dialogue` | Dialogue | `dialogue` |
| `parenthetical` | Parenthetical | `parenthetical` |
| `transition` | Transition | `transition` |

## Current baseline (do not regress)

- LWC: `force-app/main/default/lwc/scriptEditor/`
- Apex: `ScriptEditorController`, `ScriptDocumentStorageService`, `ScriptImportExportService`, `ScriptPdfController`
- Objects: `Script__c`, `Script_Document__c`, `Script_Version__c`
- Org alias: `personalDev`
- Remote: `origin` → `ScriptWriter`
