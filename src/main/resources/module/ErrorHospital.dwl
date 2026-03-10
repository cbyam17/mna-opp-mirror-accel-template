%dw 2.0
// Error Hospital Utilities

// ------------------------
// Defaults
// ------------------------
fun defaultAppName() = (Mule::p("projectName") as String) default "unknown-app"
fun defaultDomain() = (Mule::p("orgName") as String) default "unknown-org"
fun defaultErrorType() = (Mule::p("error.defaultType") as String) default "UNKNOWN_ERROR"
fun defaultErrorMessage() = (Mule::p("error.defaultMessage") as String) default "An unknown error occurred"
fun defaultErrorDescription() =
    (Mule::p("error.defaultDescription") as String)
        default "An unknown error occurred; please check integration logs with this transaction Id for more details"
fun defaultMaxRetries() = (Mule::p("errHsptl.maxRetries") as Number) default 5

// ------------------------
// Helpers
// ------------------------
fun toArray(v) =
    if (v is Array) v
    else if (v == null) []
    else [v]

fun firstError(resp) =
    (((resp.errors default []) as Array)[0]) default {}

fun collectErrorField(container, fieldName) =
    (
        (
            (((container default [])..errors) default []) map (e) -> (e[fieldName] default null)
        )
        filter ((v) -> v != null)
        map ((v) -> (v as String))
    ) joinBy "; "

// ------------------------
// Public Builders
// ------------------------
fun buildGetRecordsFromErrHsptlByIdRequest(recordIds) =
    (recordIds default []) distinctBy ((item) -> item) default []

fun buildDeleteRecordsFromErrHsptlRequest(recordIds) =
    (recordIds default []) distinctBy ((item) -> item) default []

fun buildSendRecordsToErrHsptlRequest(records, transactionId) =
    {
        appName: defaultAppName(),
        domain: defaultDomain(),
        transactionId: transactionId,
        failedRecords: (records default []) map ((o) -> do {
            var recordId = o.recordId default ""
            var createOppResp = o.createOpptyResponse default {}
            var updateOppResp = o.updateOpptyResponse default {}
            var createOliResponses = o.createOpptyProductResponses default []
            var updateOliResponses = o.updateOpptyProductResponses default []
            var deleteOliResponses = o.deleteOpptyProductResponses default []

            var defType = defaultErrorType()
            var defMsg = defaultErrorMessage()
            var defDesc = defaultErrorDescription()
            var maxRetries = defaultMaxRetries()

            var createOppFailed = ((createOppResp.success default true) == false)
            var updateOppFailed = ((updateOppResp.success default true) == false)
            var anyCreateOliFailed = (((toArray(createOliResponses)).*success default []) contains false)
            var anyUpdateOliFailed = (((toArray(updateOliResponses)).*success default []) contains false)
            var anyDeleteOliFailed = (((toArray(deleteOliResponses)).*success default []) contains false)

            var resolvedError =
                if (createOppFailed) do {
                    var e = firstError(createOppResp)
                    ---
                    {
                        errorType: (e.statusCode as String) default defType,
                        errorMessage: (e.message as String) default defMsg,
                        description: "An error occurred creating Opportunity in _TGT; please check integration logs with this transaction Id for more details"
                    }
                }
                else if (updateOppFailed) do {
                    var e = firstError(updateOppResp)
                    ---
                    {
                        errorType: (e.statusCode as String) default defType,
                        errorMessage: (e.message as String) default defMsg,
                        description: "An error occurred updating Opportunity in _TGT; please check integration logs with this transaction Id for more details"
                    }
                }
                else if (anyCreateOliFailed)
                    {
                        errorType: collectErrorField(createOliResponses, "statusCode") default defType,
                        errorMessage: collectErrorField(createOliResponses, "message") default defMsg,
                        description: "An error occurred creating OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
                    }
                else if (anyUpdateOliFailed)
                    {
                        errorType: collectErrorField(updateOliResponses, "statusCode") default defType,
                        errorMessage: collectErrorField(updateOliResponses, "message") default defMsg,
                        description: "An error occurred updating OpportunityLineItem(s) in _TGT; please check integration logs with this transaction Id for more details"
                    }
                else if (anyDeleteOliFailed)
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
                    description: (resolvedError.description default defDesc),
                    maxRetries: maxRetries
                }
            }
        })
    }

fun buildSendSystemErrorRecordsToErrHsptlRequest(records, transactionId) =
    {
        appName: defaultAppName(),
        domain: defaultDomain(),
        transactionId: transactionId,
        failedRecords: (records default []) map ((o) -> do {
            var defType = defaultErrorType()
            var defMsg = defaultErrorMessage()
            var defDesc = defaultErrorDescription()
            var maxRetries = defaultMaxRetries()

            var recordId = o.recordId default ""
            var errorData = o.errorData default {}
            // Expect object placed into errorData.message earlier; if not an object, fallback.
            var originalError =
                if ((errorData.message default null) is Object)
                    (errorData.message as Object)
                else
                    {}

            var errType = (originalError.errorType as String) default null
            var errMsg = (originalError.errorMessage as String) default null
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
        })
    }