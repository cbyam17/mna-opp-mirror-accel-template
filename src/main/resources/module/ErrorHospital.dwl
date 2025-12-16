%dw 2.0
import * from module::CommonUtil

var retryableTypes = (Mule::p('errHsptl.retryTypes') default '') splitBy ',' filter ((item, index) -> !isEmpty(item))

fun buildRetrieveRecordsFromErrorHospitalByIdRequest(data) =
    data.Id default [] distinctBy ((item, index) -> item) default []

fun buildSendErrorRecordsToErrorHospitalRequest(data, transactionId) =
    data default [] map ((item, index) -> {
        recordId: item.Id,
        transactionId: transactionId, 
        error: {
            errorType: if (!item.targetOpptyResponse.success) 'TARGET_OPPTY_MIRROR_FAILURE'
                else if (item.targetOpptyProductResponses.success contains false) 'TARGET_OPPTY_PRODUCT_MIRROR_FAILURE'
                else 'UNKNOWN_ERROR',
            errorMessage: if (!item.targetOpptyResponse.success) item.targetOpptyResponse.errors[0].message
                else if (item.targetOpptyProductResponses.success contains false) getTargetOpptyProductErrorMessages(item.targetOpptyProductResponses)
                else 'No error message available',
            //always true for demo purposes; update as needed
            //isRetryable: true,
            //maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
        }
    })

fun buildSendFailedRecordsToErrorHospitalRequest(data, transactionId) =    
    data default [] map ((item, index) -> do {
        var errorData = Batch::getLastException()
        ---
        {
            recordId: item.Id,
            transactionId: transactionId, 
            error: {
                //error details tbd
                errorType: errorData.errorType,
                errorMessage: errorData.errorMessage,
                //always true for demo purposes; update as needed
                //isRetryable: true,
                //maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
        }
    })

fun buildDeleteRecordsFromErrorHospitalRequest(data) =
    data.Id default [] distinctBy ((item, index) -> item) default []


