@IsTest
private class ScriptPdfControllerTest {
  @IsTest
  static void rendersBlocksFromWorkingDocument() {
    Script__c script = new Script__c(
      Name = 'PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    ScriptEditorController.saveScript(
      script.Id,
      '{"mode":"screenplay","blocks":[{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},{"id":2,"type":"action","value":"Lights flicker."}]}',
      '{"schemaVersion":2,"mode":"screenplay"}',
      5,
      1,
      'screenplay',
      'Autosave'
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual('PDF Script', controller.title);
    Assert.areEqual('screenplay', controller.mode);
    Assert.areEqual(2, controller.blocks.size());
    Assert.areEqual('scene-heading', controller.blocks[0].blockType);
    Assert.areEqual('INT. OFFICE - DAY', controller.blocks[0].value);
  }
}
