public without sharing  class AccountTriggerHandler {

    public static void beforeInsert(List<Account> newList,Map<Id,Account> newMap){
       
        
    }
    
     public static void beforeUpdate(List<Account> newList,Map<Id,Account> newMap){
        
         updateFullName(newList,newMap);

    }
    
     public static void afterInsert(){
        
        
    }
    
    public static void afterUpdate(List<Account> newList,Map<Id,Account> oldMap){
        createContactIfTypeChanged(newList,oldMap);
        
    }
TestClass.sayHello('test');
    
    public static void updateFullName(List<Account> newList,Map<Id,Account> oldMap){
		System.debug('oldMap '+oldMap);
        for(Account acc:newList){
            
            if(oldMap.get(acc.Id).Type != acc.Type){
                 System.debug('from '+ oldMap.get(acc.Id).Type +' values changes to ' +acc.Type);
            }
        }   
        
	}
    
     public static void createContactIfTypeChanged(List<Account> newList,Map<Id,Account> oldMap){
		System.debug('oldMap '+oldMap);
        List<Contact> conList= new List<Contact>();
        for(Account acc:newList){
            
            if(oldMap.get(acc.Id).Type != acc.Type){
                 Contact con = new Contact();
                con.AccountId=acc.Id;
                con.LastName=acc.Name;
                conList.add(con);
            }
        }   
       System.debug('test ');
         insert conList;
        
	}
}