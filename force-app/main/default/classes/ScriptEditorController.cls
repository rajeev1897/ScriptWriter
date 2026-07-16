public with sharing class ScriptEditorController {
  private static final Integer FORMAT_METADATA_LIMIT = 131072;

  @AuraEnabled
  public static LoadResponse loadScript(Id scriptId) {
    validateScriptId(scriptId);

    List<Script__c> scripts = [
      SELECT Id, Name, Last_Saved_At__c, Type__c
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
    ];
    if (scripts.isEmpty()) {
      throw handledException('The script could not be found or accessed.');
    }

    LoadResponse response = new LoadResponse();
    response.title = scripts[0].Name;
    response.mode = scripts[0].Type__c == 'Synopsis'
      ? 'synopsis'
      : 'screenplay';
    response.savedAt = scripts[0].Last_Saved_At__c;
    response.pdfUrl = '/apex/ScriptPdf?id=' + String.valueOf(scriptId);

    response.content = ScriptBlockPersistenceService.loadOrMigrateWorkingContent(
      scriptId,
      response.mode
    );

    List<Script__c> refreshed = [
      SELECT Last_Saved_At__c, Type__c
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!refreshed.isEmpty()) {
      response.mode = refreshed[0].Type__c == 'Synopsis'
        ? 'synopsis'
        : 'screenplay';
      response.savedAt = refreshed[0].Last_Saved_At__c;
    }
    return response;
  }

  @AuraEnabled
  public static SaveResponse saveScript(
    Id scriptId,
    String content,
    String formatMetadata,
    Integer wordCount,
    Integer pageCount,
    String mode,
    String saveSource,
    String dirtyBlocks,
    String deletedBlockIds
  ) {
    validateScriptId(scriptId);
    validatePayload(content, formatMetadata, wordCount, pageCount, mode);
    String normalizedSaveSource = normalizeSaveSource(saveSource);

    List<Script__c> scripts = [
      SELECT Id, Name
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
      FOR UPDATE
    ];
    if (scripts.isEmpty()) {
      throw handledException('The script could not be found or accessed.');
    }

    Script__c script = scripts[0];
    SaveResponse response = new SaveResponse();
    response.pdfUrl = '/apex/ScriptPdf?id=' + String.valueOf(scriptId);

    if (normalizedSaveSource == 'Autosave') {
      ScriptBlockPersistenceService.PersistResult persistResult = ScriptBlockPersistenceService.autosaveBlocks(
        scriptId,
        content,
        dirtyBlocks,
        deletedBlockIds,
        mode,
        wordCount,
        pageCount
      );
      response.savedAt = persistResult.savedAt;
      response.content = persistResult.content;
      response.blockIdMap = persistResult.blockIdMap;
      return response;
    }

    ScriptBlockPersistenceService.PersistResult persistResult = ScriptBlockPersistenceService.persistFullDocument(
      scriptId,
      content,
      mode
    );
    response.savedAt = persistResult.savedAt;
    response.content = persistResult.content;
    response.blockIdMap = persistResult.blockIdMap;

    if (
      normalizedSaveSource == 'Manual' ||
      normalizedSaveSource == 'Import' ||
      normalizedSaveSource == 'Export'
    ) {
      String snapshotContent = ScriptBlockPersistenceService.buildVersionSnapshot(
        scriptId
      );
      if (String.isBlank(snapshotContent)) {
        snapshotContent = String.isBlank(persistResult.content)
          ? content
          : persistResult.content;
      }

      Id snapshotVersionId = ScriptDocumentStorageService.writeSnapshotContent(
        scriptId,
        script.Name + ' ' + normalizedSaveSource + ' Snapshot',
        snapshotContent
      );
      Script_Version__c version = new Script_Version__c(
        Script__c = scriptId,
        Content__c = ScriptDocumentStorageService.truncateForLegacyField(
          snapshotContent
        ),
        Format_Metadata__c = String.isBlank(formatMetadata)
          ? JSON.serialize(
              new Map<String, Object>{
                'schemaVersion' => 3,
                'mode' => mode,
                'source' => normalizedSaveSource
              }
            )
          : formatMetadata,
        Saved_At__c = persistResult.savedAt,
        Source__c = normalizedSaveSource,
        Content_Version_Id__c = snapshotVersionId,
        Version_Label__c = normalizedSaveSource == 'Manual'
          ? 'Manual save'
          : normalizedSaveSource
      );
      Database.insert(version, AccessLevel.SYSTEM_MODE);
      response.versionId = version.Id;
      response.contentVersionId = snapshotVersionId;
    }

    return response;
  }

  @AuraEnabled
  public static SaveResponse importPlainText(
    Id scriptId,
    String plainText,
    String fileName,
    String mode
  ) {
    validateScriptId(scriptId);
    String normalizedMode = mode == 'synopsis' ? 'synopsis' : 'screenplay';
    ScriptImportExportService.ParsedDocument parsed = ScriptImportExportService.parsePlainText(
      plainText,
      normalizedMode
    );
    String content = ScriptImportExportService.toEditorJson(parsed);
    Integer wordCount = ScriptImportExportService.countWords(content);
    Integer pageCount = wordCount == 0
      ? 0
      : (Integer) Math.ceil(wordCount / 250.0);

    if (String.isNotBlank(fileName)) {
      ScriptDocumentStorageService.writeTextFile(
        scriptId,
        fileName.endsWith('.txt') ? fileName.replace('.txt', '') : fileName,
        plainText == null ? '' : plainText
      );
    }

    return saveScript(
      scriptId,
      content,
      JSON.serialize(
        new Map<String, Object>{
          'schemaVersion' => 3,
          'mode' => parsed.mode,
          'source' => 'Import'
        }
      ),
      wordCount,
      pageCount,
      parsed.mode,
      'Import',
      null,
      null
    );
  }

  @AuraEnabled
  public static ExportResponse exportPlainText(Id scriptId) {
    validateScriptId(scriptId);
    LoadResponse loaded = loadScript(scriptId);
    String plainText = ScriptImportExportService.toPlainText(loaded.content);
    String title = String.isBlank(loaded.title) ? 'Script' : loaded.title;
    Id contentVersionId = ScriptDocumentStorageService.writeTextFile(
      scriptId,
      title + ' Export',
      plainText
    );

    String snapshotContent = ScriptBlockPersistenceService.hasBlocks(scriptId)
      ? ScriptBlockPersistenceService.buildVersionSnapshot(scriptId)
      : loaded.content;

    Script_Version__c version = new Script_Version__c(
      Script__c = scriptId,
      Content__c = ScriptDocumentStorageService.truncateForLegacyField(
        snapshotContent
      ),
      Format_Metadata__c = JSON.serialize(
        new Map<String, Object>{
          'schemaVersion' => 3,
          'mode' => loaded.mode,
          'exportType' => 'txt'
        }
      ),
      Saved_At__c = System.now(),
      Source__c = 'Export',
      Content_Version_Id__c = contentVersionId,
      Version_Label__c = 'Export'
    );
    Database.insert(version, AccessLevel.SYSTEM_MODE);

    ExportResponse response = new ExportResponse();
    response.fileName = title + '.txt';
    response.plainText = plainText;
    response.contentVersionId = contentVersionId;
    response.versionId = version.Id;
    response.pdfUrl = '/apex/ScriptPdf?id=' + String.valueOf(scriptId);
    return response;
  }

  private static String normalizeSaveSource(String saveSource) {
    String normalizedSaveSource = String.isBlank(saveSource)
      ? 'Autosave'
      : saveSource;
    if (
      normalizedSaveSource != 'Autosave' &&
      normalizedSaveSource != 'Manual' &&
      normalizedSaveSource != 'Import' &&
      normalizedSaveSource != 'Export'
    ) {
      throw handledException('The save source is not supported.');
    }
    return normalizedSaveSource;
  }

  private static void validateScriptId(Id scriptId) {
    if (
      scriptId == null ||
      scriptId.getSObjectType() != Script__c.SObjectType
    ) {
      throw handledException('A valid script record is required.');
    }
  }

  private static void validatePayload(
    String content,
    String formatMetadata,
    Integer wordCount,
    Integer pageCount,
    String mode
  ) {
    if (String.isBlank(content)) {
      throw handledException('Script content is required.');
    }
    if (
      formatMetadata != null &&
      formatMetadata.length() > FORMAT_METADATA_LIMIT
    ) {
      throw handledException('The script formatting metadata is too large.');
    }
    if (
      wordCount == null ||
      wordCount < 0 ||
      pageCount == null ||
      pageCount < 0
    ) {
      throw handledException('Script counts cannot be negative.');
    }
    if (mode != 'screenplay' && mode != 'synopsis') {
      throw handledException('The document type is not supported.');
    }
  }

  private static AuraHandledException handledException(String message) {
    AuraHandledException handledError = new AuraHandledException(message);
    handledError.setMessage(message);
    return handledError;
  }

  public class LoadResponse {
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String mode { get; set; }
    @AuraEnabled
    public String content { get; set; }
    @AuraEnabled
    public Datetime savedAt { get; set; }
    @AuraEnabled
    public String pdfUrl { get; set; }
  }

  public class SaveResponse {
    @AuraEnabled
    public Id documentId { get; set; }
    @AuraEnabled
    public Id versionId { get; set; }
    @AuraEnabled
    public Id contentVersionId { get; set; }
    @AuraEnabled
    public Datetime savedAt { get; set; }
    @AuraEnabled
    public String pdfUrl { get; set; }
    @AuraEnabled
    public String content { get; set; }
    @AuraEnabled
    public Map<String, String> blockIdMap { get; set; }
  }

  public class ExportResponse {
    @AuraEnabled
    public String fileName { get; set; }
    @AuraEnabled
    public String plainText { get; set; }
    @AuraEnabled
    public Id contentVersionId { get; set; }
    @AuraEnabled
    public Id versionId { get; set; }
    @AuraEnabled
    public String pdfUrl { get; set; }
  }
}
