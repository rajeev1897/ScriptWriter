public with sharing class ScriptBlockPersistenceService {
  private static final String TYPE_SCENE_HEADING = 'scene-heading';
  private static final Set<String> VALID_BLOCK_TYPES = new Set<String>{
    'scene-heading',
    'action',
    'character',
    'dialogue',
    'parenthetical',
    'transition'
  };

  public class PersistResult {
    public Datetime savedAt;
    public String content;
    public Map<String, String> blockIdMap = new Map<String, String>();
  }

  public class EditorBlock {
    public String clientId;
    public String type;
    public String value;
    public Integer sequence;
  }

  public static Boolean hasBlocks(Id scriptId) {
    if (scriptId == null) {
      return false;
    }
    return [
        SELECT COUNT()
        FROM Script_Block__c
        WHERE Script__c = :scriptId
        WITH USER_MODE
      ] > 0;
  }

  public static String loadDocument(Id scriptId) {
    List<Script__c> scripts = [
      SELECT Id, Type__c
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
    ];
    if (scripts.isEmpty()) {
      return null;
    }

    String mode = scripts[0].Type__c == 'Synopsis' ? 'synopsis' : 'screenplay';
    List<Script_Block__c> blocks = [
      SELECT
        Id,
        Block_Type__c,
        Text__c,
        Sequence__c,
        Script_Scene__r.Sequence__c
      FROM Script_Block__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY Script_Scene__r.Sequence__c ASC, Sequence__c ASC, Id ASC
    ];

    List<Object> payloadBlocks = new List<Object>();
    for (Script_Block__c block : blocks) {
      payloadBlocks.add(
        new Map<String, Object>{
          'id' => String.valueOf(block.Id),
          'type' => normalizeBlockType(block.Block_Type__c),
          'value' => block.Text__c == null ? '' : block.Text__c
        }
      );
    }

    return JSON.serialize(
      new Map<String, Object>{ 'mode' => mode, 'blocks' => payloadBlocks }
    );
  }

  public static PersistResult autosaveBlocks(
    Id scriptId,
    String content,
    String dirtyBlocksJson,
    String deletedBlockIdsJson,
    String mode,
    Integer wordCount,
    Integer pageCount
  ) {
    Datetime savedAt = bumpScriptSavedAt(scriptId, mode);

    PersistResult result;
    if (String.isNotBlank(dirtyBlocksJson)) {
      result = upsertDirtyBlocks(
        scriptId,
        content,
        dirtyBlocksJson,
        deletedBlockIdsJson
      );
    } else {
      result = reconcileFromContent(scriptId, content, mode);
    }

    result.savedAt = savedAt;
    if (String.isBlank(result.content)) {
      result.content = hasBlocks(scriptId) ? loadDocument(scriptId) : content;
    }
    return result;
  }

  public static PersistResult persistFullDocument(
    Id scriptId,
    String content,
    String mode
  ) {
    PersistResult result = reconcileFromContent(scriptId, content, mode);
    result.savedAt = bumpScriptSavedAt(scriptId, mode);
    return result;
  }

  /**
   * Builds a schemaVersion 3 JSON snapshot from persisted scenes/blocks
   * for ContentVersion versioning. Flat blocks remain for editor compatibility.
   */
  public static String buildVersionSnapshot(Id scriptId) {
    List<Script__c> scripts = [
      SELECT Id, Type__c
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
    ];
    if (scripts.isEmpty()) {
      return null;
    }

    String mode = scripts[0].Type__c == 'Synopsis' ? 'synopsis' : 'screenplay';

    List<Script_Scene__c> scenes = [
      SELECT
        Id,
        Sequence__c,
        Scene_Heading__c,
        Location__c,
        Time_Of_Day__c,
        Summary__c
      FROM Script_Scene__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY Sequence__c ASC, Id ASC
    ];

    List<Script_Block__c> blocks = [
      SELECT
        Id,
        Block_Type__c,
        Text__c,
        Sequence__c,
        Script_Scene__c,
        Script_Scene__r.Sequence__c
      FROM Script_Block__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY Script_Scene__r.Sequence__c ASC, Sequence__c ASC, Id ASC
    ];

    Map<Id, List<Object>> blocksBySceneId = new Map<Id, List<Object>>();
    List<Object> flatBlocks = new List<Object>();
    for (Script_Block__c block : blocks) {
      Map<String, Object> blockPayload = new Map<String, Object>{
        'id' => String.valueOf(block.Id),
        'type' => normalizeBlockType(block.Block_Type__c),
        'value' => block.Text__c == null ? '' : block.Text__c,
        'sequence' => Integer.valueOf(block.Sequence__c)
      };
      flatBlocks.add(
        new Map<String, Object>{
          'id' => blockPayload.get('id'),
          'type' => blockPayload.get('type'),
          'value' => blockPayload.get('value')
        }
      );
      if (block.Script_Scene__c == null) {
        continue;
      }
      if (!blocksBySceneId.containsKey(block.Script_Scene__c)) {
        blocksBySceneId.put(block.Script_Scene__c, new List<Object>());
      }
      blocksBySceneId.get(block.Script_Scene__c).add(blockPayload);
    }

    List<Object> scenePayloads = new List<Object>();
    for (Script_Scene__c scene : scenes) {
      List<Object> sceneBlocks = blocksBySceneId.containsKey(scene.Id)
        ? blocksBySceneId.get(scene.Id)
        : new List<Object>();
      scenePayloads.add(
        new Map<String, Object>{
          'sequence' => Integer.valueOf(scene.Sequence__c),
          'heading' => scene.Scene_Heading__c,
          'location' => scene.Location__c,
          'timeOfDay' => scene.Time_Of_Day__c,
          'summary' => scene.Summary__c,
          'blocks' => sceneBlocks
        }
      );
    }

    return JSON.serialize(
      new Map<String, Object>{
        'schemaVersion' => 3,
        'mode' => mode,
        'scenes' => scenePayloads,
        'blocks' => flatBlocks
      }
    );
  }

  private static Datetime bumpScriptSavedAt(Id scriptId, String mode) {
    Datetime savedAt = System.now();
    Script__c script = new Script__c(
      Id = scriptId,
      Last_Saved_At__c = savedAt,
      Type__c = mode == 'synopsis' ? 'Synopsis' : 'Screenplay'
    );
    Database.update(script, AccessLevel.USER_MODE);
    return savedAt;
  }

  private static PersistResult reconcileFromContent(
    Id scriptId,
    String content,
    String mode
  ) {
    List<EditorBlock> editorBlocks = parseEditorBlocks(content);
    if (editorBlocks.isEmpty()) {
      editorBlocks.add(emptyBlock(mode));
    }

    deleteExistingStructure(scriptId);

    List<ScenePlan> scenePlans = deriveScenes(editorBlocks);
    Map<Integer, Id> sceneIdBySequence = insertScenes(scriptId, scenePlans);

    List<Script_Block__c> blocksToInsert = new List<Script_Block__c>();
    List<String> clientIds = new List<String>();
    for (ScenePlan scenePlan : scenePlans) {
      Integer blockSequence = 1;
      for (EditorBlock editorBlock : scenePlan.blocks) {
        blocksToInsert.add(
          new Script_Block__c(
            Script__c = scriptId,
            Script_Scene__c = sceneIdBySequence.get(scenePlan.sequence),
            Sequence__c = blockSequence,
            Block_Type__c = normalizeBlockType(editorBlock.type),
            Text__c = editorBlock.value
          )
        );
        clientIds.add(editorBlock.clientId);
        blockSequence++;
      }
    }

    if (!blocksToInsert.isEmpty()) {
      Database.insert(blocksToInsert, AccessLevel.USER_MODE);
    }

    PersistResult result = new PersistResult();
    for (Integer i = 0; i < blocksToInsert.size(); i++) {
      result.blockIdMap.put(
        clientIds[i],
        String.valueOf(blocksToInsert[i].Id)
      );
    }
    result.content = loadDocument(scriptId);
    return result;
  }

  private static PersistResult upsertDirtyBlocks(
    Id scriptId,
    String content,
    String dirtyBlocksJson,
    String deletedBlockIdsJson
  ) {
    PersistResult result = new PersistResult();
    Set<Id> deleteIds = parseIdSet(deletedBlockIdsJson);
    if (!deleteIds.isEmpty()) {
      List<Script_Block__c> doomed = [
        SELECT Id
        FROM Script_Block__c
        WHERE Id IN :deleteIds AND Script__c = :scriptId
        WITH USER_MODE
      ];
      if (!doomed.isEmpty()) {
        Database.delete(doomed, AccessLevel.USER_MODE);
      }
    }

    List<EditorBlock> dirtyBlocks = parseDirtyBlocks(dirtyBlocksJson);
    if (dirtyBlocks.isEmpty()) {
      result.content = hasBlocks(scriptId) ? loadDocument(scriptId) : content;
      return result;
    }

    Map<Id, Script_Block__c> existingById = new Map<Id, Script_Block__c>(
      [
        SELECT Id, Script_Scene__c, Block_Type__c, Text__c, Sequence__c
        FROM Script_Block__c
        WHERE Script__c = :scriptId
        WITH USER_MODE
      ]
    );

    Id fallbackSceneId = ensureSceneForScript(scriptId);
    List<Script_Block__c> toUpdate = new List<Script_Block__c>();
    List<Script_Block__c> toInsert = new List<Script_Block__c>();
    List<String> insertClientIds = new List<String>();
    List<Script_Scene__c> scenesToUpdate = new List<Script_Scene__c>();

    for (EditorBlock dirty : dirtyBlocks) {
      String blockType = normalizeBlockType(dirty.type);
      if (isScriptBlockId(dirty.clientId)) {
        Id blockId = Id.valueOf(dirty.clientId);
        if (!existingById.containsKey(blockId)) {
          continue;
        }
        Script_Block__c existing = existingById.get(blockId);
        // Build a fresh update row so USER_MODE does not attempt to write
        // non-reparentable master-detail fields from the queried record.
        Script_Block__c updateRow = new Script_Block__c(
          Id = blockId,
          Block_Type__c = blockType,
          Text__c = dirty.value
        );
        if (dirty.sequence != null) {
          updateRow.Sequence__c = dirty.sequence;
        }
        toUpdate.add(updateRow);
        result.blockIdMap.put(dirty.clientId, String.valueOf(blockId));

        if (blockType == TYPE_SCENE_HEADING && existing.Script_Scene__c != null) {
          Script_Scene__c scene = new Script_Scene__c(
            Id = existing.Script_Scene__c
          );
          applyHeadingParts(scene, dirty.value);
          scenesToUpdate.add(scene);
        }
      } else {
        Id sceneId = fallbackSceneId;
        if (blockType == TYPE_SCENE_HEADING) {
          sceneId = createScene(
            scriptId,
            nextSceneSequence(scriptId),
            dirty.value
          );
          fallbackSceneId = sceneId;
        }
        toInsert.add(
          new Script_Block__c(
            Script__c = scriptId,
            Script_Scene__c = sceneId,
            Sequence__c = dirty.sequence == null ? 1 : dirty.sequence,
            Block_Type__c = blockType,
            Text__c = dirty.value
          )
        );
        insertClientIds.add(dirty.clientId);
      }
    }

    if (!scenesToUpdate.isEmpty()) {
      Database.update(scenesToUpdate, AccessLevel.USER_MODE);
    }
    if (!toUpdate.isEmpty()) {
      Database.update(toUpdate, AccessLevel.USER_MODE);
    }
    if (!toInsert.isEmpty()) {
      Database.insert(toInsert, AccessLevel.USER_MODE);
      for (Integer i = 0; i < toInsert.size(); i++) {
        result.blockIdMap.put(
          insertClientIds[i],
          String.valueOf(toInsert[i].Id)
        );
      }
    }

    result.content = hasBlocks(scriptId) ? loadDocument(scriptId) : content;
    return result;
  }

  private static void deleteExistingStructure(Id scriptId) {
    List<Script_Block__c> blocks = [
      SELECT Id
      FROM Script_Block__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
    ];
    if (!blocks.isEmpty()) {
      Database.delete(blocks, AccessLevel.USER_MODE);
    }

    List<Script_Scene__c> scenes = [
      SELECT Id
      FROM Script_Scene__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
    ];
    if (!scenes.isEmpty()) {
      Database.delete(scenes, AccessLevel.USER_MODE);
    }
  }

  private class ScenePlan {
    public Integer sequence;
    public String heading;
    public String location;
    public String timeOfDay;
    public List<EditorBlock> blocks = new List<EditorBlock>();
  }

  private static List<ScenePlan> deriveScenes(List<EditorBlock> editorBlocks) {
    List<ScenePlan> scenes = new List<ScenePlan>();
    ScenePlan current;
    Integer sceneSequence = 0;

    for (EditorBlock editorBlock : editorBlocks) {
      String blockType = normalizeBlockType(editorBlock.type);
      Boolean startsScene =
        blockType == TYPE_SCENE_HEADING || current == null;

      if (startsScene) {
        if (current == null || blockType == TYPE_SCENE_HEADING) {
          sceneSequence++;
          current = new ScenePlan();
          current.sequence = sceneSequence;
          if (blockType == TYPE_SCENE_HEADING) {
            applyHeadingPartsToPlan(current, editorBlock.value);
          }
          scenes.add(current);
        }
      }

      current.blocks.add(editorBlock);
    }

    return scenes;
  }

  private static Map<Integer, Id> insertScenes(
    Id scriptId,
    List<ScenePlan> scenePlans
  ) {
    List<Script_Scene__c> scenes = new List<Script_Scene__c>();
    for (ScenePlan plan : scenePlans) {
      scenes.add(
        new Script_Scene__c(
          Script__c = scriptId,
          Sequence__c = plan.sequence,
          Scene_Heading__c = plan.heading,
          Location__c = plan.location,
          Time_Of_Day__c = plan.timeOfDay
        )
      );
    }
    if (!scenes.isEmpty()) {
      Database.insert(scenes, AccessLevel.USER_MODE);
    }

    Map<Integer, Id> bySequence = new Map<Integer, Id>();
    for (Script_Scene__c scene : scenes) {
      bySequence.put(Integer.valueOf(scene.Sequence__c), scene.Id);
    }
    return bySequence;
  }

  private static Id ensureSceneForScript(Id scriptId) {
    List<Script_Scene__c> scenes = [
      SELECT Id
      FROM Script_Scene__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
      ORDER BY Sequence__c ASC
      LIMIT 1
    ];
    if (!scenes.isEmpty()) {
      return scenes[0].Id;
    }
    return createScene(scriptId, 1, null);
  }

  private static Integer nextSceneSequence(Id scriptId) {
    List<AggregateResult> aggregates = [
      SELECT MAX(Sequence__c) maxSeq
      FROM Script_Scene__c
      WHERE Script__c = :scriptId
      WITH USER_MODE
    ];
    Decimal maxSeq = aggregates.isEmpty()
      ? null
      : (Decimal) aggregates[0].get('maxSeq');
    return maxSeq == null ? 1 : Integer.valueOf(maxSeq) + 1;
  }

  private static Id createScene(
    Id scriptId,
    Integer sequence,
    String heading
  ) {
    Script_Scene__c scene = new Script_Scene__c(
      Script__c = scriptId,
      Sequence__c = sequence
    );
    applyHeadingParts(scene, heading);
    Database.insert(scene, AccessLevel.USER_MODE);
    return scene.Id;
  }

  private static void applyHeadingPartsToPlan(
    ScenePlan plan,
    String heading
  ) {
    Script_Scene__c temp = new Script_Scene__c();
    applyHeadingParts(temp, heading);
    plan.heading = temp.Scene_Heading__c;
    plan.location = temp.Location__c;
    plan.timeOfDay = temp.Time_Of_Day__c;
  }

  private static void applyHeadingParts(
    Script_Scene__c scene,
    String heading
  ) {
    if (String.isBlank(heading)) {
      scene.Scene_Heading__c = null;
      scene.Location__c = null;
      scene.Time_Of_Day__c = null;
      return;
    }

    String trimmed = heading.trim();
    scene.Scene_Heading__c = truncate(trimmed, 255);

    Matcher matcher = Pattern.compile(
        '(?i)^(INT\\.?/EXT\\.?|I/E\\.?|INT\\.?|EXT\\.?)\\s+(.+?)(?:\\s+-\\s+(.+))?$'
      )
      .matcher(trimmed);
    if (matcher.matches()) {
      scene.Location__c = truncate(
        matcher.group(2) == null ? null : matcher.group(2).trim(),
        255
      );
      scene.Time_Of_Day__c = truncate(
        matcher.group(3) == null ? null : matcher.group(3).trim(),
        80
      );
    } else {
      scene.Location__c = null;
      scene.Time_Of_Day__c = null;
    }
  }

  private static List<EditorBlock> parseEditorBlocks(String content) {
    List<EditorBlock> blocks = new List<EditorBlock>();
    if (String.isBlank(content)) {
      return blocks;
    }

    Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
      content
    );
    List<Object> rawBlocks = (List<Object>) document.get('blocks');
    if (rawBlocks == null) {
      return blocks;
    }

    Integer index = 1;
    for (Object rawBlock : rawBlocks) {
      Map<String, Object> blockMap = (Map<String, Object>) rawBlock;
      EditorBlock block = new EditorBlock();
      Object rawId = blockMap.get('id');
      block.clientId = rawId == null
        ? String.valueOf(index)
        : String.valueOf(rawId);
      block.type = normalizeBlockType(
        blockMap.get('type') == null
          ? 'action'
          : String.valueOf(blockMap.get('type'))
      );
      block.value = blockMap.get('value') == null
        ? ''
        : String.valueOf(blockMap.get('value'));
      block.sequence = index;
      blocks.add(block);
      index++;
    }
    return blocks;
  }

  private static List<EditorBlock> parseDirtyBlocks(String dirtyBlocksJson) {
    List<EditorBlock> blocks = new List<EditorBlock>();
    if (String.isBlank(dirtyBlocksJson)) {
      return blocks;
    }

    List<Object> rawBlocks = (List<Object>) JSON.deserializeUntyped(
      dirtyBlocksJson
    );
    Integer index = 1;
    for (Object rawBlock : rawBlocks) {
      Map<String, Object> blockMap = (Map<String, Object>) rawBlock;
      EditorBlock block = new EditorBlock();
      Object rawId = blockMap.get('id');
      block.clientId = rawId == null
        ? String.valueOf(index)
        : String.valueOf(rawId);
      block.type = normalizeBlockType(
        blockMap.get('type') == null
          ? 'action'
          : String.valueOf(blockMap.get('type'))
      );
      block.value = blockMap.get('value') == null
        ? ''
        : String.valueOf(blockMap.get('value'));
      Object rawSequence = blockMap.get('sequence');
      if (rawSequence != null) {
        block.sequence = Integer.valueOf(String.valueOf(rawSequence));
      }
      blocks.add(block);
      index++;
    }
    return blocks;
  }

  private static Set<Id> parseIdSet(String idsJson) {
    Set<Id> ids = new Set<Id>();
    if (String.isBlank(idsJson)) {
      return ids;
    }
    List<Object> rawIds = (List<Object>) JSON.deserializeUntyped(idsJson);
    for (Object rawId : rawIds) {
      if (rawId == null) {
        continue;
      }
      String asString = String.valueOf(rawId);
      if (isScriptBlockId(asString)) {
        ids.add(Id.valueOf(asString));
      }
    }
    return ids;
  }

  private static EditorBlock emptyBlock(String mode) {
    EditorBlock block = new EditorBlock();
    block.clientId = '1';
    block.type = mode == 'synopsis' ? 'action' : TYPE_SCENE_HEADING;
    block.value = '';
    block.sequence = 1;
    return block;
  }

  private static String normalizeBlockType(String blockType) {
    if (String.isBlank(blockType)) {
      return 'action';
    }
    String normalized = blockType.trim().toLowerCase();
    // Accept picklist labels from older payloads.
    if (normalized == 'scene heading') {
      return TYPE_SCENE_HEADING;
    }
    if (VALID_BLOCK_TYPES.contains(normalized)) {
      return normalized;
    }
    return 'action';
  }

  private static Boolean isScriptBlockId(String value) {
    if (String.isBlank(value)) {
      return false;
    }
    try {
      return Id.valueOf(value).getSObjectType() == Script_Block__c.SObjectType;
    } catch (Exception error) {
      return false;
    }
  }

  private static String truncate(String value, Integer maxLength) {
    if (value == null) {
      return null;
    }
    if (value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}
