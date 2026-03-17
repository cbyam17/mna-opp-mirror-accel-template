// ============================================================================
// Error Hospital Module DataWeave
// ============================================================================

%dw 2.0
import toArray from module::CommonUtil

fun firstError(resp) =
  (((resp.errors default []) as Array)[0]) default {}

fun collectErrorField(container, fieldName) =
  do {
    var values = container
                   flatMap ((rec) -> rec.errors)
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
fun defaultMaxRetries() = (Mule::p("errHsptl.maxRetries")   as Number) default 5

fun buildGetRecordsFromErrHsptlByIdRequest(oppIds) =
  (oppIds default []) distinctBy ((item) -> item) default []

fun buildDeleteRecordsFromErrHsptlRequest(oppIds) =
  (oppIds default []) distinctBy ((item) -> item) default []

fun buildSendRecordsToErrHsptlRequest(opps, transactionId) =
  {
    appName:       defaultAppName(),
    domain:        defaultDomain(),
    transactionId: transactionId,
    failedRecords:
      (opps default []) map ((opp) ->
        do {
          var recordId = opp.Id default ""
          var createOppResp = opp.createOppResponse default {}
          var updateOppResp = opp.updateOppResponse default {}
          var createOliResponses = opp.createOliResponses default []
          var updateOliResponses = opp.updateOliResponses default []
          var deleteOliResponses = opp.deleteOliResponses default []

          var defType = defaultErrorType()
          var defMsg = defaultErrorMessage()
          var defDesc = defaultErrorDescription()
          var maxRetries = defaultMaxRetries()

          var isCreateOppFailed = ((createOppResp.success default true) == false)
          var isUpdateOppFailed = ((updateOppResp.success default true) == false)
          var isAnyCreateOliFailed = (((toArray(createOliResponses)).*success default []) contains false)
          var isAnyUpdateOliFailed = (((toArray(updateOliResponses)).*success default []) contains false)
          var isAnyDeleteOliFailed = (((toArray(deleteOliResponses)).*success default []) contains false)

          var resolvedError =
            if (isCreateOppFailed) do {
              var e = firstError(createOppResp)
              ---
              {
                errorType: (e.statusCode as String) default defType,
                errorMessage: (e.message as String) default defMsg,
                description: "An error occurred creating Opportunity in _TGT; please check integration logs with this transaction Id for more details"
              }
            }
            else if (isUpdateOppFailed) do {
              var e = firstError(updateOppResp)
              ---
              {
                errorType: (e.statusCode as String) default defType,
                errorMessage: (e.message as String) default defMsg,
                description: "An error occurred updating Opportunity in _TGT; please check integration logs with this transaction Id for more details"
              }
            }
            else if (isAnyCreateOliFailed)
              {
                errorType: collectErrorField(createOliResponses, "statusCode") default defType,
                errorMessage: collectErrorField(createOliResponses, "message") default defMsg,
                description: "An error occurred creating OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
              }
            else if (isAnyUpdateOliFailed)
              {
                errorType: collectErrorField(updateOliResponses, "statusCode") default defType,
                errorMessage: collectErrorField(updateOliResponses, "message") default defMsg,
                description: "An error occurred updating OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
              }
            else if (isAnyDeleteOliFailed)
              {
                errorType: collectErrorField(deleteOliResponses, "statusCode") default defType,
                errorMessage: collectErrorField(deleteOliResponses, "message") default defMsg,
                description: "An error occurred deleting OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
              }
            else
              {
                errorType:    defType,
                errorMessage: defMsg,
                description:  defDesc
              }
          ---
          {
            recordId: recordId,
            error: {
              errorType:   (resolvedError.errorType default defType),
              errorMessage:(resolvedError.errorMessage default defMsg),
              description: (resolvedError.description  default defDesc),
              maxRetries:  maxRetries
            }
          }
        }
      )
  }

fun buildSendSystemErrorRecordsToErrHsptlRequest(opps, transactionId) =
  {
    appName:       defaultAppName(),
    domain:        defaultDomain(),
    transactionId: transactionId,
    failedRecords:
      (opps default []) map ((opp) ->
        do {
          var defType = defaultErrorType()
          var defMsg = defaultErrorMessage()
          var defDesc = defaultErrorDescription()
          var maxRetries = defaultMaxRetries()

          var recordId = opp.Id default ""
          var errorData = opp.errorData default {}

          // Expect object placed into errorData.message earlier; if not an object, fallback.
          var originalError =
            if ((errorData.message default null) is Object)
              (errorData.message as Object)
            else
              {}

          var errType = (originalError.errorType as String) default defType
          var errMsg = (originalError.errorMessage as String) default defMsg
          var description = (Mule::p("error.defaultDescription") as String) default defDesc
          ---
          {
            recordId: recordId,
            error: {
              errorType: errType default defType,
              errorMessage: errMsg default defMsg,
              description: description default defDesc,
              maxRetries: maxRetries
            }
          }
        }
      )
  }