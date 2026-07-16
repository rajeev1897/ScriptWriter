# Agent 04 — Manual Versions + Import/Export on Block Model

## Role

Wire Manual save, Import `.txt`, Download `.txt`/PDF to scene/block storage + ContentVersion snapshots.

## Prerequisites

Agents 01–03 deployed and committed.

## Branch

`feature/script-block-model`

## Build

### Manual save / Cmd+S

1. Persist all scenes/blocks (reconcile full editor state)
2. Build structured JSON snapshot:
   ```json
   {
     "schemaVersion": 3,
     "mode": "screenplay",
     "scenes": [{ "sequence": 1, "heading": "...", "blocks": [...] }],
     "blocks": [...]
   }
   ```
3. Store as `ContentVersion` (JSON)
4. Insert `Script_Version__c` with `Source__c=Manual`, `Saved_At__c`, `Content_Version_Id__c`, optional `Version_Label__c`
5. Do **not** duplicate every block into version child rows

### Import `.txt`

- Parse via `ScriptImportExportService` (improve if needed)
- Replace or rebuild scenes/blocks for the script
- Store original `.txt` as ContentVersion on Script
- Create version with `Source__c=Import`

### Export `.txt`

- Assemble plain text from blocks in order
- Optional ContentVersion + `Source__c=Export`
- Browser download unchanged

### PDF

- Update `ScriptPdfController` to load from scenes/blocks first, File/legacy fallback second
- Keep `/apex/ScriptPdf?id=scriptId`

### Tests

- Manual creates exactly one `Script_Version__c` + ContentVersion
- Autosave still creates zero versions
- Import/export Apex tests
- PDF controller test with block data

## Do not

- Delete `Script_Document__c` yet

## Acceptance

- Save version creates File snapshot + version row
- Upload/download work against block storage
- Deploy + tests pass

## End of agent

1. Deploy with Apex tests
2. Commit: `Align versions and import export with scene blocks.`
3. Stop and report
