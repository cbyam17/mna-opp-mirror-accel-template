// ============================================================================
// Opportunity Line Item Module DataWeave
// ============================================================================

%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil
import mapToTgt, mapToSrc from module::PricebookEntry

fun buildQueryOlisByOppId_SRC(oppIds) =
  {
    // Adjust SOQL per requirements
    query:
      "SELECT Id, PricebookEntryId, OpportunityId, UnitPrice, Quantity " ++
      "FROM OpportunityLineItem WHERE OpportunityId IN (" ++ generateIdInClause(oppIds) ++ ")",
    queryParams:
      (oppIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        // minor clarity fix: use (acc, item) order
        reduce ((acc = {}, item) -> acc ++ item)
  }
fun buildQueryOlisByOppExternalId_TGT(oppIds) =
  {
    // Adjust SOQL per requirements
    query:
      "SELECT Id, PricebookEntryId, OpportunityId, Opportunity.Oppty_Id_SRC__c " ++
      "FROM OpportunityLineItem " ++
      "WHERE Opportunity.Oppty_Id_SRC__c IN (" ++ generateIdInClause(oppIds) ++ ")",
    queryParams:
      (oppIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

fun transformCreateOlis_TGT(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToCreate default []) map ((oli) ->
      do {
        // Adjust field mapping as needed
        var transformedData =
          {
            OpportunityId:
              if (!isEmpty(opp.existingOpp)) opp.existingOpp.Id else opp.createOppResponse.id,
            PricebookEntryId: mapToTgt(oli.PricebookEntryId as String),
            Quantity:         ((oli.Quantity  default 0) as Number),
            UnitPrice:        ((oli.UnitPrice default 0) as Number),
            Oppty_Product_Id_SRC__c: oli.Id
          }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull))
          transformedData mergeWith { fieldsToNull: fieldsToNull }
        else
          transformedData
      }
    )
  )
fun transformUpdateOlis_TGT(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToUpdate default []) map ((oli) ->
      do {
        var matchSrc =
          ((opp.olis default [])
            filter ((item) -> mapToTgt(item.PricebookEntryId as String) == oli.PricebookEntryId))[0]

        var transformedData =
          {
            Id:        oli.Id,
            Quantity:  ((matchSrc.Quantity  default 0) as Number),
            UnitPrice: ((matchSrc.UnitPrice default 0) as Number)
          }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull))
          transformedData mergeWith { fieldsToNull: fieldsToNull }
        else
          transformedData
      }
    )
  )

fun transformDeleteOlis_TGT(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToDelete default []) map ((oli) -> oli.Id)
  )

fun getOppIdsForOlisToCreate(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToCreate default []) map ((oli) -> 
      (opp.Id as String)))

fun getOppIdsForOlisToUpdate(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToUpdate default []) map ((oli) -> 
      (opp.Id as String)))

fun getOppIdsForOlisToDelete(opps) =
  (opps default []) flatMap ((opp) ->
    (opp.olisToDelete default []) map ((oli) -> 
      (opp.Id as String)))
  
fun getMatchingOliResponses(responsesMap, oppId) =
  (responsesMap default [])
    filter ((oli) -> (oli.srcOppId == oppId))