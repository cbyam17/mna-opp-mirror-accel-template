// ============================================================================
// Opportunity Module DataWeave
// ============================================================================

%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull, toArray, firstOrNull, truncate from module::CommonUtil
import mapToTgt, mapToSrc from module::PricebookEntry
import defaultErrorDescription, firstError, collectErrorField from module::ErrorHospital

fun buildQueryOppsByDate_SRC(fromLastRunDateTime, toLastRunDateTime) =
  {
    query:
      "SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
      "FROM Opportunity " ++
      "WHERE Is_Mirror_Scope_TGT__c = true AND " ++
      "((Ready_To_Mirror_Date_Time_TGT__c >= :watermarkLastRunDateTime " ++
      "AND Ready_To_Mirror_Date_Time_TGT__c < :watermarkCurrentRunDateTime) " ++
      "OR Mirror_Error_TGT__c != null)",
    queryParams: {
      watermarkLastRunDateTime:  fromLastRunDateTime,
      watermarkCurrentRunDateTime: toLastRunDateTime
    }
  }

fun buildQueryOppsById_SRC(ids) =
  {
    query:
      "SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
      "FROM Opportunity WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",
    queryParams:
      (ids default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

fun buildQueryOppsByExternalId_TGT(externalIds) =
  {
    query:
      "SELECT Id, Oppty_Id_SRC__c " ++
      "FROM Opportunity WHERE Oppty_Id_SRC__c IN (" ++ generateIdInClause(externalIds) ++ ")",
    queryParams:
      (externalIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

fun enrichOppsWithQueryResults(
  opps,
  existingOpps,
  olis,
  existingOlis,
  existingAccts,
  existingErrHsptlRecords
) =
  (opps default []) map ((opp) -> do {
      var recExistingAcct =
        firstOrNull((existingAccts default [])
          filter ((item) -> item.Id == opp.Account.Acct_Id_TGT__c))

      var recExistingOpp =
        firstOrNull((existingOpps default [])
          filter ((item) -> item.Oppty_Id_SRC__c == opp.Id))

      var recExistingErrHsptlRecord =
        firstOrNull((existingErrHsptlRecords default [])
          filter ((item) -> item.recordId == opp.Id))

      var recExistingOlis =
        (existingOlis default [])
          filter ((item)  -> item.Opportunity.Oppty_Id_SRC__c == opp.Id)

      var recOlis =
        (olis default [])
          filter ((item) -> item.OpportunityId == opp.Id)

      var recExistingPbes =
        (recExistingOlis default [])
          map ((oli) -> oli.PricebookEntryId)

      var recPbes =
        (recOlis default [])
          map ((oli) -> oli.PricebookEntryId)

      var recOlisToCreate =
        (recOlis default [])
          filter ((item) -> !(recExistingPbes contains mapToTgt(item.PricebookEntryId as String)))

      var recOlisToUpdate =
        (recExistingOlis default [])
          filter ((item) -> (recPbes contains mapToSrc(item.PricebookEntryId as String)))

      var recOlisToDelete =
        (recExistingOlis default [])
          filter ((item) -> !(recPbes contains mapToSrc(item.PricebookEntryId as String)))
      ---
      opp ++ {
        existingAcct: recExistingAcct default null,
        existingOpp: recExistingOpp default null,
        existingErrHsptlRecord: recExistingErrHsptlRecord default null,
        existingOlis: recExistingOlis default [],
        olis: recOlis default [],
        olisToCreate: recOlisToCreate default [],
        olisToUpdate: recOlisToUpdate default [],
        olisToDelete: recOlisToDelete default []
      }
    })

fun transformOpp_TGT(opp) = do {
  var prefixedName =
    if (!isEmpty(opp.Name))
      "SRC - " ++ opp.Name
    else
      null
  ---
  {
    AccountId:        opp.Account.Acct_Id_TGT__c,
    Oppty_Id_SRC__c:  opp.Id,
    OwnerId:          opp.existingAcct.OwnerId,
    // Use truncate if you need strict length: truncate(prefixedName, 120)
    Name:             prefixedName, 
    StageName:        opp.StageName,
    CloseDate:
      if (!isEmpty(opp.CloseDate))
        opp.CloseDate as Date { format: "yyyy-MM-dd" }
      else
        null,
  }
}

fun transformCreateOpps_TGT(opps) =
  (opps default []) map ((opp) -> do {
    var transformed  = transformOpp_TGT(opp)
    var fieldsToNull = buildFieldsToNull(transformed)
    ---
    if (!isEmpty(fieldsToNull))
      transformed mergeWith { fieldsToNull: fieldsToNull }
    else
      transformed
  })

fun transformUpdateOpps_TGT(opps) =
  (opps default []) map ((opp) -> do {
    var transformed =
      transformOpp_TGT(opp) ++ {
          Id: opp.existingOpp.Id
        }
      var fieldsToNull = buildFieldsToNull(transformed)
      ---
      if (!isEmpty(fieldsToNull))
        transformed mergeWith { fieldsToNull: fieldsToNull }
      else
        transformed
    }
  )

fun buildErrorMessage(objectType, message) =
  "_TGT mirror error - " ++ (objectType default "") ++ ": " ++ (message default "Unknown error")

fun transformWritebackOpps_SRC(opps) =
  (opps default []) map ((opp) -> do {
    var oppId = opp.Id default ""
    var upsertedOppId =
      if (!isEmpty(opp.existingOpp))
        opp.existingOpp.Id
      else if ((opp.createOppResponse.success default false) == true)
        opp.createOppResponse.id
      else null

    var defDesc = defaultErrorDescription()

    var createOppResp = opp.createOppResponse default {}
    var updateOppResp = opp.updateOppResponse default {}
    var createOliResponses = opp.createOliResponses default []
    var updateOliResponses = opp.updateOliResponses default []
    var deleteOliResponses = opp.deleteOliResponses default []

    var isCreateOppFailed = ((createOppResp.success default true) == false) //confirm default
    var isUpdateOppFailed = ((updateOppResp.success default true) == false) //confirm default
    var isAnyCreateOliFailed = (((toArray(createOliResponses)).*success default []) contains false)
    var isAnyUpdateOliFailed = (((toArray(updateOliResponses)).*success default []) contains false)
    var isAnyDeleteOliFailed = (((toArray(deleteOliResponses)).*success default []) contains false)

    var isSystemError = ((opp.isSystemError default false) == true)

    var resolvedError =
      if (isCreateOppFailed) do {
        var e = firstError(createOppResp)
        ---
        buildErrorMessage("Opportunity", (e.message as String) default defDesc)
      }
      else if (isUpdateOppFailed) do {
        var e = firstError(updateOppResp)
        ---
        buildErrorMessage("Opportunity", (e.message as String) default defDesc)
      }
      else if (isAnyCreateOliFailed) do {
        var errMsgs = collectErrorField(createOliResponses, "message")
        ---
        buildErrorMessage("OpportunityLineItem", (errMsgs as String) default defDesc)
      }
      else if (isAnyUpdateOliFailed) do {
        var errMsgs = collectErrorField(updateOliResponses, "message")
        ---
        buildErrorMessage("OpportunityLineItem", (errMsgs as String) default defDesc)
      }
      else if (isAnyDeleteOliFailed) do {
        var errMsgs = collectErrorField(deleteOliResponses, "message")
        ---
        buildErrorMessage("OpportunityLineItem", (errMsgs as String) default defDesc)
      }
      else if (isSystemError)
        buildErrorMessage("Opportunity", (defDesc as String))
      else
        null

    var transformed =
      {
        Id:                  oppId,
        Oppty_Id_TGT__c:     upsertedOppId,
        Mirror_Error_TGT__c: truncate(resolvedError, 255)
      }

    var fieldsToNull = buildFieldsToNull(transformed)
    ---
    if (!isEmpty(fieldsToNull))
      transformed mergeWith { fieldsToNull: fieldsToNull }
    else
      transformed
  })