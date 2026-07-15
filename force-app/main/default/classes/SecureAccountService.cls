/**
 * SecureAccountService
 * Demonstrates:
 * 1. Object-level security (CRUD)
 * 2. Field-level security (FLS)
 * 3. Record-level security (Sharing)
 * 4. User-mode enforcement
 */
public with sharing class SecureAccountService {

    /**
     * READ Accounts securely
     */
    public static List<Account> getAccounts() {

        // 1️⃣ OBJECT-LEVEL SECURITY (READ)
      SMSUtils.checkPermission(true, false, false, false);

        if (!Schema.sObjectType.Account.fields.Phone.isAccessible()) {
            throw new SecurityException('No read access to Phone field');
        }
        // 2️⃣ SOQL (NO FLS TRUST YET)
        List<Account> accList = [
            SELECT Id, Name, Phone, Industry
            FROM Account WITH SECURITY_ENFORCED
        ];

        // 3️⃣ FIELD-LEVEL SECURITY (READ)
        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.READABLE,
                accList
            );

        return (List<Account>) decision.getRecords();
    }

    /**
     * CREATE Account securely
     */
    public static Id createAccount(Account acc) {

        // 1️⃣ OBJECT-LEVEL SECURITY (CREATE)
        if (!Schema.sObjectType.Account.isCreateable()) {
            throw new SecurityException('No create permission on Account');
        }

        // 2️⃣ FIELD-LEVEL SECURITY (CREATE)
        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.CREATABLE,
                new List<Account>{ acc }
            );

        insert decision.getRecords();
        return decision.getRecords()[0].Id;
    }

    /**
     * UPDATE Account securely
     */
    public static void updateAccount(Account acc) {

        // 1️⃣ OBJECT-LEVEL SECURITY (UPDATE)
        if (!Schema.sObjectType.Account.isUpdateable()) {
            throw new SecurityException('No update permission on Account');
        }

        // 2️⃣ FIELD-LEVEL SECURITY (UPDATE)
        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<Account>{ acc }
            );

        update decision.getRecords();
    }

    /**
     * DELETE Account securely
     */
    public static void deleteAccount(Id accId) {

        // 1️⃣ OBJECT-LEVEL SECURITY (DELETE)
        if (!Schema.sObjectType.Account.isDeletable()) {
            throw new SecurityException('No delete permission on Account');
        }

        // 2️⃣ RECORD-LEVEL SECURITY
        // with sharing enforces OWD + Sharing Rules
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Id = :accId
            LIMIT 1
        ];

        delete acc;
    }
}
