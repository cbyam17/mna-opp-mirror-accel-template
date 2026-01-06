%dw 2.0
import * from module::CommonUtil

var retryableTypes = (Mule::p('errHsptl.retryTypes') default '') splitBy ',' filter ((item, index) -> !isEmpty(item))

fun buildRetrieveRecordsFromErrorHospitalByIdRequest(data) =
    data.Id default [] distinctBy ((item, index) -> item) default []

fun buildSendErrorRecordsToErrorHospitalRequest(data, transactionId) =
    data default [] map ((item, index) -> {
        recordId: item.Id,
        transactionId: transactionId, 
        error: if (!item.targetOpptyResponse.success)
            {
                errorType: item.targetOpptyResponse.errors[0].statusCode,
                errorMessage: item.targetOpptyResponse.errors[0].message,
                description: 'Target oppty mirror failure',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
            else if (item.targetOpptyProductResponses.success contains false)
            {
                errorType: getOpptyProductErrorStatusCodes(item.targetOpptyProductResponses),
                errorMessage: getOpptyProductErrorMessages(item.targetOpptyProductResponses),
                description: 'Target oppty product mirror failure',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
            else if (!item.sourceOpptyResponse.success)
            {
                errorType: item.sourceOpptyResponse.errors[0].statusCode,
                errorMessage: item.sourceOpptyResponse.errors[0].message,
                description: 'Source oppty writeback failure',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
            else if (item.sourceOpptyProductResponses.success contains false)
            {
                errorType: getOpptyProductErrorStatusCodes(item.sourceOpptyProductResponses),
                errorMessage: getOpptyProductErrorMessages(item.sourceOpptyProductResponses),
                description: 'Source oppty product writeback failure',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
            else 
            {
                errorType: 'UNKNOWN_ERROR',
                errorMessage: 'An unknown error occurred.',
                description: 'Unknown failure during processing',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
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
                errorType: errorData.errorType,
                errorMessage: errorData.errorMessage,
                description: 'Batch processing failure',
                //always true for demo purposes; update as needed
                isRetryable: true,
                maxRetries: Mule::p('errHsptl.maxRetries') as Number default 5
            }
        }
    })

fun buildDeleteRecordsFromErrorHospitalRequest(data) =
    data.Id default [] distinctBy ((item, index) -> item) default []


