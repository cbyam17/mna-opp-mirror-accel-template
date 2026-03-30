// ============================================================================
// Opportunity Module DataWeave
// ============================================================================

%dw 2.0
import buildFieldsToNullList, generateIdInClause, toArray, firstOrNull, truncate from module::CommonUtils
import defaultErrorDescription, firstError, collectErrorField from module::ErrorHospital

// Adjust SOQL query as needed
fun buildQueryOppsByDate_SRC(fromlastRunDateTime, tolastRunDateTime) =
  {
    query:
      "SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
          "FROM Opportunity " ++
          "WHERE Is_In_Mirror_Scope_TGT__c = true AND " ++
          "((Ready_To_Mirror_Datetime_TGT__c >= :watermarklastRunDateTime " ++
          "AND Ready_To_Mirror_Datetime_TGT__c < :watermarkCurrentRunDateTime) " ++
          "OR Mirror_Error_TGT__c != null)",
    queryParams: {
        watermarklastRunDateTime: fromlastRunDateTime,
        watermarkCurrentRunDateTime: tolastRunDateTime
      }
  }

// Adjust SOQL query as needed per Salesforce schema
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

// Adjust SOQL query as needed per Salesforce schema
fun buildQueryOppsByExternalId_TGT(externalIds) =
  {
    query:
      "SELECT Id, Opp_Id_SRC__c " ++
          "FROM Opportunity WHERE Opp_Id_SRC__c IN (" ++ generateIdInClause(externalIds) ++ ")",
    queryParams:
      (externalIds default [])
          distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

// Adjust field mapping as needed per Salesforce schema
fun enrichOppsWithQueryResults(
                               opps,
                               existingOpps,
                               olis,
                               existingOlis,
                               existingAccts,
                               existingErrHsptlRecords
) =
  (opps default []) map ((opp) -> do {
          var oppExistingAcct =
            firstOrNull((existingAccts default [])
                filter ((item) -> item.Id == opp.Account.Acct_Id_TGT__c))

          var oppExistingOpp =
            firstOrNull((existingOpps default [])
                filter ((item) -> item.Opp_Id_SRC__c == opp.Id))

          var oppExistingErrHsptlRecord =
            firstOrNull((existingErrHsptlRecords default [])
                filter ((item) -> item.recordId == opp.Id))

          var oppExistingOlis =
            (existingOlis default [])
              filter ((item) -> item.Opportunity.Opp_Id_SRC__c == opp.Id)

          var oppOlis =
            (olis default [])
              filter ((item) -> item.OpportunityId == opp.Id)
      
          var oppOlisToDelete =
            (oppExistingOlis default [])
              filter ((item) ->
                  not (oppOlis.Id contains item.Oli_Id_SRC__c)
                )
          ---
          opp ++ {
                existingAcct: oppExistingAcct,
                existingOpp: oppExistingOpp,
                existingErrHsptlRecord: oppExistingErrHsptlRecord,
                existingOlis: oppExistingOlis,
                olis: oppOlis,
                olisToDelete: oppOlisToDelete
              }
        })

// Adjust field mapping as needed per Salesforce schema
fun transformUpsertOpps_TGT(opps) =
  (opps default []) map ((opp) -> do {
          var tgtOppId = opp.existingOpp.Id default null
          var srcOppId = opp.Id default null
          var acctId = opp.Account.Acct_Id_TGT__c default null
          var ownerId = opp.existingAcct.OwnerId default null
          var prefixedName =
            if (!isEmpty(opp.Name))
              "SRC - " ++ opp.Name
            else
              null
          var stageName = opp.StageName default null
          var closeDate =
            if (!isEmpty(opp.CloseDate))
              opp.CloseDate as Date { format: "yyyy-MM-dd" }
            else
              null

          var transformed =
            {
              Id: tgtOppId,
              Opp_Id_SRC__c: srcOppId,
              AccountId: acctId,
              OwnerId: ownerId,
              Name: truncate(prefixedName, 120),
              StageName: stageName,
              CloseDate: closeDate
            }

          var fieldsToNullList = buildFieldsToNullList(transformed)
          ---
          transformed ++ 
              (fieldsToNull: fieldsToNullList)

        })

// Adjust field mapping as needed per Salesforce schema
fun transformWritebackOpps_SRC(opps) =
  (opps default []) map ((opp) -> do {

          var defDesc = defaultErrorDescription()

          var upsertOppResponse = opp.upsertOppResponse default {}
          var upsertOliResponses = opp.upsertOliResponses default []
          var deleteOliResponses = opp.deleteOliResponses default []

          var isUpsertOppSuccess = (upsertOppResponse.success default false)
          var isUpsertOlisSuccess = !(((toArray(upsertOliResponses)).success default []) contains false)
          var isDeleteOlisSuccess = !(((toArray(deleteOliResponses)).success default []) contains false)

          var isSystemError = (opp.isSystemError default false)

          var srcOppId = opp.Id default null
          var tgtOppId =
            if (!isEmpty(opp.existingOpp))
              opp.existingOpp.Id
            else if (isUpsertOppSuccess)
              opp.upsertOppResponse.id
            else
              null

          var resolvedError =
            if (isSystemError)
              buildErrorMessage(
                "System Error",
                (defDesc as String)) // add error message?
            else if (!isUpsertOppSuccess) do {
                var e = firstError(upsertOppResponse)
                ---
                buildErrorMessage(
                  "Opportunity",
                  (e.message as String) default defDesc)
              }
            else if (!isUpsertOlisSuccess) do {
                var errMsgs = collectErrorField(upsertOliResponses, "message")
                ---
                buildErrorMessage(
                  "OpportunityLineItem",
                  (errMsgs as String) default defDesc)
              }
            else if (!isDeleteOlisSuccess) do {
                var errMsgs = collectErrorField(deleteOliResponses, "message")
                ---
                buildErrorMessage(
                  "OpportunityLineItem",
                  (errMsgs as String) default defDesc)
              }
            else
              null
    
          var transformed =
            {
              Id: srcOppId,
              Opp_Id_TGT__c: tgtOppId,
              Mirror_Error_TGT__c: truncate(resolvedError, 255)
            }
    
          var fieldsToNullList = buildFieldsToNullList(transformed)
          ---
          transformed ++ 
              (fieldsToNull: fieldsToNullList)
        })

fun buildErrorMessage(objectType, message) =
  "_TGT mirror error - " ++ (objectType default "") ++ ": " ++ (message default "Unknown error")

fun getMatchingOppResponse(responses, index) =
  {
 	  matchingResponse: responses[index] default null
  } 