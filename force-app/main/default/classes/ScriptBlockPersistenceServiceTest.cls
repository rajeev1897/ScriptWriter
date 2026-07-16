@IsTest
private class ScriptBlockPersistenceServiceTest {
  private static final String MULTI_SCENE_CONTENT =
    '{"mode":"screenplay","blocks":[' +
    '{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},' +
    '{"id":2,"type":"action","value":"Morgan types."},' +
    '{"id":3,"type":"scene-heading","value":"EXT. STREET - NIGHT"},' +
    '{"id":4,"type":"action","value":"Rain falls."}' +
    ']}';

  @TestSetup
  static void createScript() {
    insert new Script__c(
      Name = 'Block Persistence Test',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
  }

  @IsTest
  static void reconcileCreatesOrderedScenesAndBlocks() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Test.startTest();
    ScriptBlockPersistenceService.PersistResult result = ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );
    Test.stopTest();

    List<Script_Scene__c> scenes = [
      SELECT Sequence__c, Scene_Heading__c, Location__c, Time_Of_Day__c
      FROM Script_Scene__c
      WHERE Script__c = :script.Id
      ORDER BY Sequence__c ASC
    ];
    List<Script_Block__c> blocks = [
      SELECT
        Sequence__c,
        Block_Type__c,
        Text__c,
        Script_Scene__r.Sequence__c
      FROM Script_Block__c
      WHERE Script__c = :script.Id
      ORDER BY Script_Scene__r.Sequence__c ASC, Sequence__c ASC
    ];

    Assert.areEqual(2, scenes.size());
    Assert.areEqual('INT. OFFICE - DAY', scenes[0].Scene_Heading__c);
    Assert.areEqual('OFFICE', scenes[0].Location__c);
    Assert.areEqual('DAY', scenes[0].Time_Of_Day__c);
    Assert.areEqual('EXT. STREET - NIGHT', scenes[1].Scene_Heading__c);
    Assert.areEqual(4, blocks.size());
    Assert.areEqual('scene-heading', blocks[0].Block_Type__c);
    Assert.areEqual('action', blocks[1].Block_Type__c);
    Assert.areEqual(1, Integer.valueOf(blocks[0].Script_Scene__r.Sequence__c));
    Assert.areEqual(2, Integer.valueOf(blocks[2].Script_Scene__r.Sequence__c));
    Assert.isTrue(result.blockIdMap.containsKey('1'));
    Assert.isTrue(result.blockIdMap.containsKey('4'));
    Assert.isTrue(result.content.contains('INT. OFFICE - DAY'));
    Assert.isTrue(result.content.contains('Rain falls.'));
  }

  @IsTest
  static void loadDocumentReturnsBlocksInSequenceOrder() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );

    Test.startTest();
    String content = ScriptBlockPersistenceService.loadDocument(script.Id);
    Test.stopTest();

    Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
      content
    );
    List<Object> blocks = (List<Object>) document.get('blocks');
    Assert.areEqual(4, blocks.size());
    Assert.areEqual(
      'INT. OFFICE - DAY',
      ((Map<String, Object>) blocks[0]).get('value')
    );
    Assert.areEqual(
      'Morgan types.',
      ((Map<String, Object>) blocks[1]).get('value')
    );
    Assert.areEqual(
      'EXT. STREET - NIGHT',
      ((Map<String, Object>) blocks[2]).get('value')
    );
    Assert.areEqual(
      'Rain falls.',
      ((Map<String, Object>) blocks[3]).get('value')
    );
  }

  @IsTest
  static void buildVersionSnapshotIncludesScenesAndSchemaVersion() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );

    Test.startTest();
    String snapshot = ScriptBlockPersistenceService.buildVersionSnapshot(
      script.Id
    );
    Test.stopTest();

    Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
      snapshot
    );
    Assert.areEqual(3, Integer.valueOf(String.valueOf(document.get('schemaVersion'))));
    Assert.areEqual('screenplay', document.get('mode'));
    List<Object> scenes = (List<Object>) document.get('scenes');
    List<Object> blocks = (List<Object>) document.get('blocks');
    Assert.areEqual(2, scenes.size());
    Assert.areEqual(4, blocks.size());
    Map<String, Object> firstScene = (Map<String, Object>) scenes[0];
    Assert.areEqual('INT. OFFICE - DAY', firstScene.get('heading'));
    Assert.areEqual('OFFICE', firstScene.get('location'));
    Assert.areEqual(2, ((List<Object>) firstScene.get('blocks')).size());
  }

  @IsTest
  static void autosaveWithoutDirtyBlocksCreatesNoVersion() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];

    Test.startTest();
    ScriptBlockPersistenceService.PersistResult result = ScriptBlockPersistenceService.autosaveBlocks(
      script.Id,
      MULTI_SCENE_CONTENT,
      null,
      null,
      'screenplay',
      8,
      1
    );
    Test.stopTest();

    Assert.isNotNull(result.savedAt);
    Assert.areEqual(
      4,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Version__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      result.savedAt,
      [SELECT Last_Saved_At__c FROM Script__c WHERE Id = :script.Id]
      .Last_Saved_At__c
    );
  }

  @IsTest
  static void dirtyAutosaveUpdatesOnlyProvidedBlocks() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );

    Script_Block__c actionBlock = [
      SELECT Id, Text__c
      FROM Script_Block__c
      WHERE Script__c = :script.Id AND Block_Type__c = 'action'
      ORDER BY Script_Scene__r.Sequence__c ASC, Sequence__c ASC
      LIMIT 1
    ];
    String dirtyJson =
      '[{"id":"' +
      actionBlock.Id +
      '","type":"action","value":"Morgan rewrites.","sequence":2}]';

    Test.startTest();
    ScriptBlockPersistenceService.PersistResult result = ScriptBlockPersistenceService.autosaveBlocks(
      script.Id,
      MULTI_SCENE_CONTENT,
      dirtyJson,
      null,
      'screenplay',
      8,
      1
    );
    Test.stopTest();

    Script_Block__c updated = [
      SELECT Text__c
      FROM Script_Block__c
      WHERE Id = :actionBlock.Id
    ];
    Assert.areEqual('Morgan rewrites.', updated.Text__c);
    Assert.areEqual(
      4,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Version__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      String.valueOf(actionBlock.Id),
      result.blockIdMap.get(String.valueOf(actionBlock.Id))
    );
  }

  @IsTest
  static void defaultSceneCreatedWhenNoSceneHeading() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    String content =
      '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"Cold open."}]}';

    Test.startTest();
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      content,
      'screenplay'
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Scene__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
  }

  @IsTest
  static void dirtyAutosaveInsertsAndDeletesBlocks() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );

    Script_Block__c doomed = [
      SELECT Id, Text__c
      FROM Script_Block__c
      WHERE Script__c = :script.Id
      ORDER BY Script_Scene__r.Sequence__c DESC, Sequence__c DESC
      LIMIT 1
    ];
    Assert.areEqual('Rain falls.', doomed.Text__c);
    String dirtyJson =
      '[{"id":9,"type":"Scene Heading","value":"INT. LAB - DAY","sequence":1},' +
      '{"id":10,"type":"dialogue","value":"Hello.","sequence":2}]';
    String deletedJson = '["' + doomed.Id + '"]';

    Test.startTest();
    ScriptBlockPersistenceService.PersistResult result = ScriptBlockPersistenceService.autosaveBlocks(
      script.Id,
      MULTI_SCENE_CONTENT,
      dirtyJson,
      deletedJson,
      'screenplay',
      10,
      1
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Script_Block__c WHERE Id = :doomed.Id]
    );
    Assert.isTrue(result.blockIdMap.containsKey('9'));
    Assert.isTrue(result.blockIdMap.containsKey('10'));
    Boolean foundHello = false;
    for (Script_Block__c block : [
      SELECT Text__c
      FROM Script_Block__c
      WHERE Script__c = :script.Id
    ]) {
      if (block.Text__c == 'Hello.') {
        foundHello = true;
      }
    }
    Assert.isTrue(foundHello);
    Assert.isTrue(ScriptBlockPersistenceService.hasBlocks(script.Id));
  }

  @IsTest
  static void dirtyAutosaveSyncsSceneHeadingText() {
    Script__c script = [SELECT Id FROM Script__c LIMIT 1];
    ScriptBlockPersistenceService.persistFullDocument(
      script.Id,
      MULTI_SCENE_CONTENT,
      'screenplay'
    );

    Script_Block__c heading = [
      SELECT Id, Script_Scene__c
      FROM Script_Block__c
      WHERE Script__c = :script.Id AND Block_Type__c = 'scene-heading'
      ORDER BY Script_Scene__r.Sequence__c ASC
      LIMIT 1
    ];
    String dirtyJson =
      '[{"id":"' +
      heading.Id +
      '","type":"scene-heading","value":"INT. KITCHEN - MORNING","sequence":1}]';

    Test.startTest();
    ScriptBlockPersistenceService.autosaveBlocks(
      script.Id,
      MULTI_SCENE_CONTENT,
      dirtyJson,
      null,
      'screenplay',
      8,
      1
    );
    Test.stopTest();

    Script_Scene__c scene = [
      SELECT Scene_Heading__c, Location__c, Time_Of_Day__c
      FROM Script_Scene__c
      WHERE Id = :heading.Script_Scene__c
    ];
    Assert.areEqual('INT. KITCHEN - MORNING', scene.Scene_Heading__c);
    Assert.areEqual('KITCHEN', scene.Location__c);
    Assert.areEqual('MORNING', scene.Time_Of_Day__c);
  }
}
