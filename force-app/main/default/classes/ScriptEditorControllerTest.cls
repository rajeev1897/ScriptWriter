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
  static void manualSaveCreatesContentVersionSnapshotAndVersionRow() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Test.startTest();
    ScriptEditorController.SaveResponse response = ScriptEditorController.saveScript(
      script.Id,
      SCENE_CONTENT,
      '{"schemaVersion":3,"mode":"screenplay"}',
      4,
      1,
      'screenplay',
      'Manual',
      null,
      null
    );
    Test.stopTest();

    List<Script_Version__c> versions = [
      SELECT
        Content__c,
        Content_Version_Id__c,
        Format_Metadata__c,
        Saved_At__c,
        Source__c,
        Version_Label__c
      FROM Script_Version__c
      WHERE Script__c = :script.Id
    ];
    Assert.areEqual(1, versions.size());
    Script_Version__c version = versions[0];

    Assert.areEqual(version.Id, response.versionId);
    Assert.areEqual(version.Content_Version_Id__c, response.contentVersionId);
    Assert.isNotNull(version.Content_Version_Id__c);
    Assert.areEqual('Manual', version.Source__c);
    Assert.areEqual('Manual save', version.Version_Label__c);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Document__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );

    ContentVersion snapshot = [
      SELECT VersionData, PathOnClient
      FROM ContentVersion
      WHERE Id = :version.Content_Version_Id__c
    ];
    String snapshotJson = snapshot.VersionData.toString();
    Assert.isTrue(snapshot.PathOnClient.endsWith('.json'));
    Assert.isTrue(snapshotJson.contains('"schemaVersion":3'));
    Assert.isTrue(snapshotJson.contains('"scenes"'));
    Assert.isTrue(snapshotJson.contains('INT. OFFICE - DAY'));
  }

  @IsTest
  static void autosavePersistsBlocksWithoutCreatingVersion() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":3,"mode":"screenplay"}',
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
      '{"schemaVersion":3,"mode":"synopsis"}',
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
      '{"schemaVersion":3,"mode":"screenplay"}',
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
  static void loadMigratesFileBackedDocumentOnFirstOpen() {
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
    Assert.isTrue(response.content.contains('First draft'));
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      'Migrated',
      [
          SELECT Storage_Mode__c
          FROM Script_Document__c
          WHERE Id = :document.Id
        ]
        .Storage_Mode__c
    );
    Assert.isNotNull(
      [
          SELECT Content_Document_Id__c
          FROM Script_Document__c
          WHERE Id = :document.Id
        ]
        .Content_Document_Id__c
    );

    ScriptEditorController.LoadResponse secondLoad = ScriptEditorController.loadScript(
      script.Id
    );
    Assert.areEqual(response.content, secondLoad.content);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
  }

  @IsTest
  static void loadMigratesLegacyContentFieldOnly() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    insert new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'Legacy',
      Content__c = SCENE_CONTENT,
      Word_Count__c = 4,
      Page_Count__c = 1
    );

    Test.startTest();
    ScriptEditorController.LoadResponse response = ScriptEditorController.loadScript(
      script.Id
    );
    Test.stopTest();

    Assert.isTrue(response.content.contains('INT. OFFICE - DAY'));
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Scene__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      'Migrated',
      [
          SELECT Storage_Mode__c
          FROM Script_Document__c
          WHERE Script__c = :script.Id
          LIMIT 1
        ]
        .Storage_Mode__c
    );
  }

  @IsTest
  static void loadDoesNotMigrateWhenDocumentHasNoContent() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    insert new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'Legacy',
      Content__c = null
    );

    Test.startTest();
    ScriptEditorController.LoadResponse response = ScriptEditorController.loadScript(
      script.Id
    );
    Test.stopTest();

    Assert.isNull(response.content);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      'Legacy',
      [
          SELECT Storage_Mode__c
          FROM Script_Document__c
          WHERE Script__c = :script.Id
          LIMIT 1
        ]
        .Storage_Mode__c
    );
  }

  @IsTest
  static void importPlainTextRebuildsBlocksAndCreatesImportVersion() {
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

    Assert.isNull(response.documentId);
    Assert.isNotNull(response.versionId);
    Assert.isNotNull(response.contentVersionId);
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
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Document__c WHERE Script__c = :script.Id]
    );
    Assert.isTrue(
      [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :script.Id
        ] > 0
    );
  }

  @IsTest
  static void exportPlainTextCreatesDownloadableSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":3,"mode":"screenplay"}',
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
    Assert.isTrue(
      response.downloadUrl.contains('/sfc/servlet.shepherd/version/download/')
    );
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
  static void exportPdfCreatesFileAndVersionSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      SCENE_CONTENT,
      '{"schemaVersion":3,"mode":"screenplay"}',
      4,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    Test.startTest();
    ScriptEditorController.ExportResponse response = ScriptEditorController.exportPdf(
      script.Id
    );
    Test.stopTest();

    Assert.areEqual('Autosave Test.pdf', response.fileName);
    Assert.isNotNull(response.contentVersionId);
    Assert.isNotNull(response.versionId);
    Assert.isTrue(response.pdfUrl.contains('/apex/ScriptPdf?id='));
    Assert.isTrue(
      response.downloadUrl.contains('/sfc/servlet.shepherd/version/download/')
    );

    ContentVersion pdfVersion = [
      SELECT PathOnClient, Title
      FROM ContentVersion
      WHERE Id = :response.contentVersionId
    ];
    Assert.isTrue(pdfVersion.PathOnClient.endsWith('.pdf'));

    Script_Version__c exportVersion = [
      SELECT Version_Label__c, Format_Metadata__c, Content_Version_Id__c
      FROM Script_Version__c
      WHERE Id = :response.versionId
    ];
    Assert.areEqual('PDF Export', exportVersion.Version_Label__c);
    Assert.areEqual(response.contentVersionId, exportVersion.Content_Version_Id__c);
    Assert.isTrue(exportVersion.Format_Metadata__c.contains('"exportType":"pdf"'));
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
