public inherited sharing class TestClass {

    // I need count of all testObject records per account
    // abc= 3
    // dikson = 2
    public static void sayHello(String accountName) {
           List<Account> accountList= [Select Id,Name from Account where Name =: accountName];
        List<Account> accountList1= [Select Id,Name from Account where Name = 'Dickenson plcrtrtt'];
        System.debug('accountList '+accountList);
        System.debug('accountList1 '+accountList1); 
        List<Account> updateAccountList = new List<Account> ();
   
       
        For(Account acc: accountList){
         Account acc2= new Account();
         acc2.Id = acc.Id;
         acc2.AccountNumber='1234';
            updateAccountList.add(acc2);
        }
        update updateAccountList;
            
            
    
        
        
    }

}