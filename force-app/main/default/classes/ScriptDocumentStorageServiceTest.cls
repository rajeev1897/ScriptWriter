@IsTest
private class ScriptDocumentStorageServiceTest {
  @IsTest
  static void readWorkingContentPrefersFileThenLegacyField() {
    Script__c script = new Script__c(
      Name = 'Storage Service Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    String fileContent =
      '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"From file"}]}';
    String legacyContent =
      '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"From field"}]}';

    Script_Document__c document = new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'File',
      Content__c = legacyContent
    );
    insert document;
    document.Content_Document_Id__c = ScriptDocumentStorageService.writeWorkingContent(
      document.Id,
      null,
      'Working Draft',
      fileContent
    );
    update document;

    Test.startTest();
    String readFromFile = ScriptDocumentStorageService.readWorkingContent(
      document
    );
    document.Content_Document_Id__c = null;
    String readFromField = ScriptDocumentStorageService.readWorkingContent(
      document
    );
    Test.stopTest();

    Assert.areEqual(fileContent, readFromFile);
    Assert.areEqual(legacyContent, readFromField);
    Assert.isNull(ScriptDocumentStorageService.readWorkingContent(null));
  }

  @IsTest
  static void readVersionContentPrefersContentVersion() {
    Script__c script = new Script__c(
      Name = 'Version Storage Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    String snapshot =
      '{"schemaVersion":3,"mode":"screenplay","scenes":[],"blocks":[]}';
    Id contentVersionId = ScriptDocumentStorageService.writeSnapshotContent(
      script.Id,
      'Version Snapshot',
      snapshot
    );

    Script_Version__c version = new Script_Version__c(
      Script__c = script.Id,
      Content__c = '{"fallback":true}',
      Content_Version_Id__c = contentVersionId,
      Saved_At__c = System.now(),
      Source__c = 'Manual',
      Version_Label__c = 'Manual save'
    );
    insert version;

    Test.startTest();
    String fromVersion = ScriptDocumentStorageService.readVersionContent(
      version
    );
    version.Content_Version_Id__c = null;
    String fromField = ScriptDocumentStorageService.readVersionContent(version);
    Test.stopTest();

    Assert.areEqual(snapshot, fromVersion);
    Assert.areEqual('{"fallback":true}', fromField);
    Assert.isNull(ScriptDocumentStorageService.readVersionContent(null));
  }

  @IsTest
  static void truncateForLegacyFieldRespectsLongTextLimit() {
    Assert.areEqual(
      'short',
      ScriptDocumentStorageService.truncateForLegacyField('short')
    );
    Assert.isNull(ScriptDocumentStorageService.truncateForLegacyField(null));
    Assert.areEqual(
      '',
      ScriptDocumentStorageService.truncateForLegacyField('')
    );

    String oversized = 'x'.repeat(131073);
    Assert.isNull(
      ScriptDocumentStorageService.truncateForLegacyField(oversized)
    );
  }

  @IsTest
  static void writeTextFileCreatesTxtContentVersion() {
    Script__c script = new Script__c(
      Name = 'Text File Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    Test.startTest();
    Id versionId = ScriptDocumentStorageService.writeTextFile(
      script.Id,
      'Export Draft',
      'INT. OFFICE - DAY'
    );
    Test.stopTest();

    ContentVersion version = [
      SELECT PathOnClient, VersionData
      FROM ContentVersion
      WHERE Id = :versionId
    ];
    Assert.isTrue(version.PathOnClient.endsWith('.txt'));
    Assert.areEqual('INT. OFFICE - DAY', version.VersionData.toString());
  }

  @IsTest
  static void writePdfFileCreatesPdfContentVersion() {
    Script__c script = new Script__c(
      Name = 'PDF File Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    Blob pdfBody = Blob.valueOf('%PDF-1.4 mock');

    Test.startTest();
    Id versionId = ScriptDocumentStorageService.writePdfFile(
      script.Id,
      'Export Draft',
      pdfBody
    );
    String downloadUrl = ScriptDocumentStorageService.contentVersionDownloadUrl(
      versionId
    );
    Test.stopTest();

    ContentVersion version = [
      SELECT PathOnClient, VersionData
      FROM ContentVersion
      WHERE Id = :versionId
    ];
    Assert.isTrue(version.PathOnClient.endsWith('.pdf'));
    Assert.areEqual('%PDF-1.4 mock', version.VersionData.toString());
    Assert.isTrue(
      downloadUrl.contains('/sfc/servlet.shepherd/version/download/')
    );
    Assert.isNull(ScriptDocumentStorageService.contentVersionDownloadUrl(null));
  }
}
