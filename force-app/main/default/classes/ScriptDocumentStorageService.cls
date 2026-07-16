public with sharing class ScriptDocumentStorageService {
  private static final Integer LONG_TEXT_LIMIT = 131072;

  public static String readWorkingContent(Script_Document__c document) {
    if (document == null) {
      return null;
    }

    if (String.isNotBlank(document.Content_Document_Id__c)) {
      String fileContent = readLatestDocumentContent(
        document.Content_Document_Id__c
      );
      if (fileContent != null) {
        return fileContent;
      }
    }

    return document.Content__c;
  }

  public static String readVersionContent(Script_Version__c version) {
    if (version == null) {
      return null;
    }

    if (String.isNotBlank(version.Content_Version_Id__c)) {
      List<ContentVersion> versions = [
        SELECT VersionData
        FROM ContentVersion
        WHERE Id = :version.Content_Version_Id__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!versions.isEmpty() && versions[0].VersionData != null) {
        return versions[0].VersionData.toString();
      }
    }

    return version.Content__c;
  }

  public static Id writeWorkingContent(
    Id linkedEntityId,
    Id existingContentDocumentId,
    String title,
    String content
  ) {
    ContentVersion version = new ContentVersion();
    version.Title = sanitizeTitle(title);
    version.PathOnClient = sanitizeTitle(title) + '.json';
    version.VersionData = Blob.valueOf(content);
    if (existingContentDocumentId != null) {
      version.ContentDocumentId = existingContentDocumentId;
    } else {
      version.FirstPublishLocationId = linkedEntityId;
    }
    Database.insert(version, AccessLevel.SYSTEM_MODE);

    ContentVersion inserted = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return inserted.ContentDocumentId;
  }

  public static Id writeSnapshotContent(
    Id linkedEntityId,
    String title,
    String content
  ) {
    ContentVersion version = new ContentVersion();
    version.Title = sanitizeTitle(title);
    version.PathOnClient = sanitizeTitle(title) + '.json';
    version.VersionData = Blob.valueOf(content);
    version.FirstPublishLocationId = linkedEntityId;
    Database.insert(version, AccessLevel.SYSTEM_MODE);
    return version.Id;
  }

  public static Id writeTextFile(
    Id linkedEntityId,
    String title,
    String content
  ) {
    ContentVersion version = new ContentVersion();
    version.Title = sanitizeTitle(title);
    version.PathOnClient = sanitizeTitle(title) + '.txt';
    version.VersionData = Blob.valueOf(content);
    version.FirstPublishLocationId = linkedEntityId;
    Database.insert(version, AccessLevel.SYSTEM_MODE);
    return version.Id;
  }

  public static String readLatestDocumentContent(Id contentDocumentId) {
    List<ContentVersion> versions = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (versions.isEmpty() || versions[0].VersionData == null) {
      return null;
    }
    return versions[0].VersionData.toString();
  }

  public static String truncateForLegacyField(String content) {
    if (String.isBlank(content)) {
      return content;
    }
    if (content.length() <= LONG_TEXT_LIMIT) {
      return content;
    }
    return null;
  }

  private static String sanitizeTitle(String title) {
    String safeTitle = String.isBlank(title) ? 'Script' : title.trim();
    safeTitle = safeTitle.replaceAll('[\\\\/:*?"<>|]', '-');
    return safeTitle.left(80);
  }
}
