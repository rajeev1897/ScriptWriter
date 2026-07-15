@IsTest
private class ScriptEditorControllerTest {
  private static final String FIRST_CONTENT = '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"First draft"}]}';
  private static final String SECOND_CONTENT = '{"mode":"synopsis","blocks":[{"id":1,"type":"action","value":"Revised draft"}]}';

  @TestSetup
  static void createScript() {
    insert new Script__c(
      Name = 'Autosave Test',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
  }

  @IsTest
  static void manualSaveCreatesDocumentAndSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Test.startTest();
    ScriptEditorController.SaveResponse response = ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":1,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Manual'
    );
    Test.stopTest();

    Script_Document__c document = [
      SELECT Content__c, Format_Metadata__c, Word_Count__c, Page_Count__c
      FROM Script_Document__c
      WHERE Script__c = :script.Id
    ];
    Script_Version__c version = [
      SELECT Content__c, Format_Metadata__c, Saved_At__c, Source__c
      FROM Script_Version__c
      WHERE Script__c = :script.Id
    ];
    script = [
      SELECT Last_Saved_At__c, Type__c
      FROM Script__c
      WHERE Id = :script.Id
    ];

    Assert.areEqual(document.Id, response.documentId);
    Assert.areEqual(version.Id, response.versionId);
    Assert.areEqual(FIRST_CONTENT, document.Content__c);
    Assert.areEqual(document.Content__c, version.Content__c);
    Assert.areEqual(document.Format_Metadata__c, version.Format_Metadata__c);
    Assert.areEqual(2, document.Word_Count__c);
    Assert.areEqual(1, document.Page_Count__c);
    Assert.areEqual('Manual', version.Source__c);
    Assert.areEqual(response.savedAt, version.Saved_At__c);
    Assert.areEqual(response.savedAt, script.Last_Saved_At__c);
    Assert.areEqual('Screenplay', script.Type__c);
  }

  @IsTest
  static void laterSaveUpdatesDocumentAndCreatesSnapshot() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":1,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Autosave'
    );

    Test.startTest();
    ScriptEditorController.saveScript(
      script.Id,
      SECOND_CONTENT,
      '{"schemaVersion":1,"mode":"synopsis"}',
      2,
      1,
      'synopsis',
      'Manual'
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Document__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Version__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      SECOND_CONTENT,
      [
        SELECT Content__c
        FROM Script_Document__c
        WHERE Script__c = :script.Id
      ]
      .Content__c
    );
    Assert.areEqual(
      'Synopsis',
      [SELECT Type__c FROM Script__c WHERE Id = :script.Id].Type__c
    );
  }

  @IsTest
  static void loadReturnsCurrentDocument() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptEditorController.saveScript(
      script.Id,
      FIRST_CONTENT,
      '{"schemaVersion":1,"mode":"screenplay"}',
      2,
      1,
      'screenplay',
      'Autosave'
    );

    Test.startTest();
    ScriptEditorController.LoadResponse response = ScriptEditorController.loadScript(
      script.Id
    );
    Test.stopTest();

    Assert.areEqual('Autosave Test', response.title);
    Assert.areEqual('screenplay', response.mode);
    Assert.areEqual(FIRST_CONTENT, response.content);
    Assert.isNotNull(response.savedAt);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Version__c WHERE Script__c = :script.Id]
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
