// ============================================================================
// Opportunity Line Item Module DataWeave
// ============================================================================

%dw 2.0
import buildFieldsToNullList, generateIdInClause, firstOrNull from module::CommonUtils
import mapToTgt from module::PricebookEntry

// Adjust SOQL query as needed per Salesforce schema
fun buildQueryOlisByOppId_SRC(oppIds) =
  {
    query:
      "SELECT Id, PricebookEntryId, OpportunityId, UnitPrice, Quantity " ++
          "FROM OpportunityLineItem WHERE OpportunityId IN (" ++ generateIdInClause(oppIds) ++ ")",
    queryParams:
      (oppIds default [])
          distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

// Adjust SOQL query as needed per Salesforce schema
fun buildQueryOlisByOppExternalId_TGT(oppIds) =
  {
    query:
      "SELECT Id, Oli_Id_SRC__c, PricebookEntryId, OpportunityId, Opportunity.Opp_Id_SRC__c " ++
          "FROM OpportunityLineItem " ++
          "WHERE Opportunity.Opp_Id_SRC__c IN (" ++ generateIdInClause(oppIds) ++ ")",
    queryParams:
      (oppIds default [])
          distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

// Adjust field mapping as needed per Salesforce schema
fun transformUpsertOlis_TGT(opps) =
  (opps default []) flatMap ((opp) ->
        (opp.olis default []) map ((oli) -> do {
                var srcOliId = oli.Id default null
                var tgtOliId = firstOrNull(
                    (opp.existingOlis default [])
                      filter ((item) -> item.Oli_Id_SRC__c == srcOliId)
                                  map $.Id
        ) default null
                var oppId =
                  if (!isEmpty(opp.existingOpp))
                    opp.existingOpp.Id
                  else if (opp.upsertOppResponse.success default false)
                    opp.upsertOppResponse.id
                  else null
                var pbeId = mapToTgt(oli.PricebookEntryId as String) default null
                var quantity = (oli.Quantity default 0) as Number
                var unitPrice = (oli.UnitPrice default 0) as Number

                var transformed =
                  {
                    (Id: tgtOliId) if (!isEmpty(tgtOliId)),
                    Oli_Id_SRC__c: srcOliId,
                    OpportunityId: oppId,
                    PricebookEntryId: pbeId,
                    Quantity: quantity,
                    UnitPrice: unitPrice,
                  }
          
                var fieldsToNullList = buildFieldsToNullList(transformed)
                ---
                transformed ++ 
                    (fieldsToNull: fieldsToNullList)
              })
      )

fun transformDeleteOlis_TGT(opps) =
  (opps default []) flatMap ((opp) ->
        (opp.olisToDelete default [])
          map ((oli) -> oli.Id)
      )

fun getOppIdsForOlis(opps, operation) =
  if (operation == "upsert")
    (opps default []) flatMap ((opp) ->
          (opp.olis default []) map ((oli) -> 
                (opp.Id as String)))
  else if (operation == "delete")
    (opps default []) flatMap ((opp) ->
          (opp.olisToDelete default []) map ((oli) -> 
                (opp.Id as String)))
  else
    []
  
fun buildOliResponsesMap(oppIds, oliResponses) =
  do {
    var zipped = (oppIds default []) zip (oliResponses default [])
    ---
    zipped default [] map ((oli) -> 
          oli[1] ++ { 
                oppId: oli[0]
              })
  }

fun getMatchingOliResponses(responsesMap, oppId) =
  {
    matchingResponses: (responsesMap default [])
        filter ((item) -> (item.oppId == oppId))
  }