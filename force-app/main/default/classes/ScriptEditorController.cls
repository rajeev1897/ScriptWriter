public with sharing class ScriptEditorController {
  private static final Integer LONG_TEXT_LIMIT = 131072;

  @AuraEnabled(cacheable=true)
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

    List<Script_Document__c> documents = [
      SELECT Content__c
      FROM Script_Document__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];

    LoadResponse response = new LoadResponse();
    response.title = scripts[0].Name;
    response.mode = scripts[0].Type__c == 'Synopsis'
      ? 'synopsis'
      : 'screenplay';
    response.savedAt = scripts[0].Last_Saved_At__c;
    response.content = documents.isEmpty() ? null : documents[0].Content__c;
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
    String saveSource
  ) {
    validateScriptId(scriptId);
    validatePayload(content, formatMetadata, wordCount, pageCount, mode);
    String normalizedSaveSource = String.isBlank(saveSource)
      ? 'Autosave'
      : saveSource;
    if (
      normalizedSaveSource != 'Autosave' &&
      normalizedSaveSource != 'Manual'
    ) {
      throw handledException('The save source is not supported.');
    }

    List<Script__c> scripts = [
      SELECT Id
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
      FOR UPDATE
    ];
    if (scripts.isEmpty()) {
      throw handledException('The script could not be found or accessed.');
    }

    Datetime savedAt = System.now();
    Script__c script = scripts[0];
    script.Last_Saved_At__c = savedAt;
    script.Type__c = mode == 'synopsis' ? 'Synopsis' : 'Screenplay';
    Database.update(script, AccessLevel.USER_MODE);

    List<Script_Document__c> documents = [
      SELECT Id
      FROM Script_Document__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];

    Script_Document__c document = documents.isEmpty()
      ? new Script_Document__c(Script__c = scriptId)
      : documents[0];
    document.Content__c = content;
    document.Format_Metadata__c = formatMetadata;
    document.Word_Count__c = wordCount;
    document.Page_Count__c = pageCount;
    if (document.Id == null) {
      Database.insert(document, AccessLevel.USER_MODE);
    } else {
      Database.update(document, AccessLevel.USER_MODE);
    }

    SaveResponse response = new SaveResponse();
    response.documentId = document.Id;
    response.savedAt = savedAt;
    if (normalizedSaveSource == 'Manual') {
      Script_Version__c version = new Script_Version__c(
        Script__c = scriptId,
        Content__c = content,
        Format_Metadata__c = formatMetadata,
        Saved_At__c = savedAt,
        Source__c = 'Manual'
      );
      Database.insert(version, AccessLevel.USER_MODE);
      response.versionId = version.Id;
    }
    return response;
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
      content.length() > LONG_TEXT_LIMIT ||
      (formatMetadata != null &&
      formatMetadata.length() > LONG_TEXT_LIMIT)
    ) {
      throw handledException('The script is too large to save.');
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
  }

  public class SaveResponse {
    @AuraEnabled
    public Id documentId { get; set; }
    @AuraEnabled
    public Id versionId { get; set; }
    @AuraEnabled
    public Datetime savedAt { get; set; }
  }
}
