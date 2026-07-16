@IsTest
private class ScriptEditorControllerTest {
  private static final String FIRST_CONTENT = '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"First draft"}]}';
  private static final String SECOND_CONTENT = '{"mode":"synopsis","blocks":[{"id":1,"type":"action","value":"Revised draft"}]}';
  private static final String SCENE_CONTENT =
    '{"mode":"screenplay","blocks":[' +
    '{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},' +
    '{"id":2,"type":"action","value":"First draft"}' +
    ']}';

  @TestSetup
  static void createScript() {
    insert new Script__c(
      Name = 'Autosave Test',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
  }

  @IsTest
  static void manualSaveCreatesFileBackedDocumentAndSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Test.startTest();
    ScriptEditorController.SaveResponse response = ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":2,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Manual',
      null,
      null
    );
    Test.stopTest();

    Script_Document__c document = [
      SELECT
        Content__c,
        Content_Document_Id__c,
        Storage_Mode__c,
        Format_Metadata__c,
        Word_Count__c,
        Page_Count__c
      FROM Script_Document__c
      WHERE Script__c = :script.Id
    ];
    Script_Version__c version = [
      SELECT
        Content__c,
        Content_Version_Id__c,
        Format_Metadata__c,
        Saved_At__c,
        Source__c
      FROM Script_Version__c
      WHERE Script__c = :script.Id
    ];

    Assert.areEqual(document.Id, response.documentId);
    Assert.areEqual(version.Id, response.versionId);
    Assert.areEqual('File', document.Storage_Mode__c);
    Assert.isNotNull(document.Content_Document_Id__c);
    Assert.isNotNull(version.Content_Version_Id__c);
    Assert.areEqual('Manual', version.Source__c);
    Assert.areEqual(2, document.Word_Count__c);
    Assert.areEqual(1, document.Page_Count__c);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
  }

  @IsTest
  static void autosavePersistsBlocksWithoutCreatingVersion() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":2,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    Test.startTest();
    ScriptEditorController.SaveResponse response = ScriptEditorController.saveScript(
      script.Id,
      SECOND_CONTENT,
      '{"schemaVersion":2,"mode":"synopsis"}',
      2,
      1,
      'synopsis',
      'Autosave',
      null,
      null
    );
    Test.stopTest();

    Assert.isNotNull(response.savedAt);
    Assert.isTrue(response.content.contains('Revised draft'));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Version__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Document__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      'Synopsis',
      [SELECT Type__c FROM Script__c WHERE Id = :script.Id].Type__c
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
  }

  @IsTest
  static void loadPrefersBlocksOverFileDocument() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":2,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Manual',
      null,
      null
    );
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      SCENE_CONTENT,
      'screenplay'
    );

    Test.startTest();
    ScriptEditorController.LoadResponse response = ScriptEditorController.loadScript(
      script.Id
    );
    Test.stopTest();

    Assert.areEqual('Autosave Test', response.title);
    Assert.areEqual('screenplay', response.mode);
    Assert.isTrue(response.content.contains('INT. OFFICE - DAY'));
    Assert.isTrue(response.content.contains('First draft'));
    Assert.isTrue(response.pdfUrl.contains('/apex/ScriptPdf?id='));
  }

  @IsTest
  static void loadReturnsFileBackedDocumentWhenNoBlocks() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Script_Document__c document = new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'File',
      Content__c = FIRST_CONTENT,
      Word_Count__c = 2,
      Page_Count__c = 1
    );
    insert document;
    Id contentDocumentId = ScriptDocumentStorageService.writeWorkingContent(
      document.Id,
      null,
      'Legacy Working Draft',
      FIRST_CONTENT
    );
    document.Content_Document_Id__c = contentDocumentId;
    update document;

    Test.startTest();
    ScriptEditorController.LoadResponse response = ScriptEditorController.loadScript(
      script.Id
    );
    Test.stopTest();

    Assert.areEqual('Autosave Test', response.title);
    Assert.areEqual('screenplay', response.mode);
    Assert.areEqual(FIRST_CONTENT, response.content);
  }

  @IsTest
  static void importPlainTextCreatesWorkingFileAndVersion() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    String plainText = 'INT. OFFICE - DAY\n\nMORGAN\nHello there.';

    Test.startTest();
    ScriptEditorController.SaveResponse response = ScriptEditorController.importPlainText(
      script.Id,
      plainText,
      'draft.txt',
      'screenplay'
    );
    Test.stopTest();

    Assert.isNotNull(response.documentId);
    Assert.isNotNull(response.versionId);
    Assert.isTrue(response.content.contains('INT. OFFICE - DAY'));
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Script_Version__c
        WHERE Script__c = :script.Id AND Source__c = 'Import'
      ]
    );
    Assert.isTrue(
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id] > 0
    );
  }

  @IsTest
  static void exportPlainTextCreatesDownloadableSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":2,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    Test.startTest();
    ScriptEditorController.ExportResponse response = ScriptEditorController.exportPlainText(
      script.Id
    );
    Test.stopTest();

    Assert.areEqual('Autosave Test.txt', response.fileName);
    Assert.isTrue(response.plainText.contains('First draft'));
    Assert.isNotNull(response.contentVersionId);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Script_Version__c
        WHERE Script__c = :script.Id AND Source__c = 'Export'
      ]
    );
  }

  @IsTest
  static void rejectsNonScriptIds() {
    Account account = new Account(Name = 'Not a script');
    insert account;

    Test.startTest();
    try {
      ScriptEditorController.loadScript(account.Id);
      Assert.fail('Expected an AuraHandledException.');
    } catch (AuraHandledException error) {
      Assert.isTrue(error.getMessage().contains('valid script'));
    }
    Test.stopTest();
  }
}
