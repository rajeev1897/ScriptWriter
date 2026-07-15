trigger AccountTrigger on Account (before insert,before update,before delete,after insert,after update,after delete,
                                  after undelete) {

                                      if (Trigger.isBefore && Trigger.isUpdate){
                                          AccountTriggerHandler.beforeUpdate(trigger.new,trigger.oldMap);
                                      }
                                       if (Trigger.isAfter && Trigger.isUpdate){
                                          AccountTriggerHandler.afterUpdate(trigger.new,trigger.oldMap);
                                      }
                                      
                                                   
}