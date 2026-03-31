// ============================================================================
// Error Hospital Module DataWeave
// ============================================================================

%dw 2.0
import toArray from module::CommonUtils

fun firstError(resp) =
  (((resp.errors default []) as Array)[0]) default {}

fun collectErrorField(container, fieldName) =
  do {
    var values =
      container flatMap ((rec) -> rec.errors)
        map ((e) -> e[fieldName])
    ---
    (values map (v) ->
          if (v is Array)
            ((v map ($ as String)) joinBy ", ")
          else
            (v as String)
    ) joinBy "; "
  }

fun defaultAppName() = (Mule::p("projectName") as String) default "unknown-app"
fun defaultDomain() = (Mule::p("orgName") as String) default "unknown-org"
fun defaultErrorType() = (Mule::p("error.defaultType") as String) default "UNKNOWN_ERROR"
fun defaultErrorMessage() = (Mule::p("error.defaultMessage") as String) default "An unknown error occurred"

fun defaultErrorDescription() =
  (Mule::p("error.defaultDescription") as String)
  default "An unknown error occurred; please check integration logs with this transaction Id for more details"

fun defaultMaxRetries() = (Mule::p("errHsptl.maxRetries") as Number) default 5

fun buildGetRecordsFromErrHsptlByIdRequest(oppIds) =
  (oppIds default []) distinctBy ((item) -> item) default []

fun buildDeleteRecordsFromErrHsptlRequest(oppIds) =
  (oppIds default []) distinctBy ((item) -> item) default []

fun buildSendFailedRecordsToErrHsptlRequest(opps, transactionId) =
  {
    appName: defaultAppName(),
    domain: defaultDomain(),
    transactionId: transactionId,
    failedRecords:
      (opps default []) map ((opp) -> do {
              var upsertOppResponse = opp.upsertOppResponse default {}
              var upsertOliResponses = opp.upsertOliResponses default []
              var deleteOliResponses = opp.deleteOliResponses default []

              var defType = defaultErrorType()
              var defMsg = defaultErrorMessage()
              var defDesc = defaultErrorDescription()
              var maxRetries = defaultMaxRetries()

              var isUpsertOppSuccess = (upsertOppResponse.success default true)
              var isUpsertOlisSuccess = !(((toArray(upsertOliResponses)).*success default []) contains false)
              var isDeleteOlisSuccess = !(((toArray(deleteOliResponses)).*success default []) contains false)

              var recordId = opp.Id default ""
              var resolvedError =
                if (!isUpsertOppSuccess) do {
                    var e = firstError(upsertOppResponse)
                    ---
                    {
                      errorType: (e.statusCode as String) default defType,
                      errorMessage: (e.message as String) default defMsg,
                      description: "An error occurred upserting Opportunity in _TGT; please check integration logs with this transaction Id for more details"
                    }
                  }
                else if (!isUpsertOlisSuccess)
                  {
                    errorType: collectErrorField(upsertOliResponses, "statusCode") default defType,
                    errorMessage: collectErrorField(upsertOliResponses, "message") default defMsg,
                    description: "An error occurred upserting OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
                  }
                else if (!isDeleteOlisSuccess)
                  {
                    errorType: collectErrorField(deleteOliResponses, "statusCode") default defType,
                    errorMessage: collectErrorField(deleteOliResponses, "message") default defMsg,
                    description: "An error occurred deleting OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
                  }
                else
                  {
                    errorType: defType,
                    errorMessage: defMsg,
                    description: defDesc
                  }
              ---
              {
                recordId: recordId,
                error: {
                    errorType: (resolvedError.errorType default defType),
                    errorMessage: (resolvedError.errorMessage default defMsg),
                    description: (resolvedError.description  default defDesc),
                    maxRetries: maxRetries
                  }
              }
            })
  }

fun buildSendSystemErrorRecordsToErrHsptlRequest(opps, transactionId) =
  {
    appName: defaultAppName(),
    domain: defaultDomain(),
    transactionId: transactionId,
    failedRecords:
      (opps default []) map ((opp) -> do {
              var defType = defaultErrorType()
              var defMsg = defaultErrorMessage()
              var defDesc = defaultErrorDescription()
              var maxRetries = defaultMaxRetries()

              var recordId = opp.Id default null
              var errorData = opp.systemErrorData default {}

              var errorType = (errorData.errorType as String) default defType
              var errorMessage = (errorData.errorMessage as String) default defMsg
              var description = defDesc
              ---
              {
                recordId: recordId,
                error: {
                    errorType: errorType,
                    errorMessage: errorMessage,
                    description: description,
                    maxRetries: maxRetries
                  }
              }
            })
  }
