%dw 2.0

var retryableTypes = (Mule::p("errHsptl.retryTypes") default "") splitBy "," filter ((item) -> !isEmpty(item))

fun buildGetRecordsFromErrHsptlByIdRequest(data) =
    data.Id default [] distinctBy ((item) -> item) default []

fun buildSendFailedRecordsToErrHsptlRequest(records, transactionId) =
    records default [] map ((item) -> {
        recordId: item.Id,
        transactionId: transactionId,
        error: if (!isEmpty(item.upsertOpptyError))
            // oppty mirror failure
            {
                errorType: item.upsertOpptyError.statusCode default "UNKNOWN_ERROR",
                errorMessage: item.upsertOpptyError.message default "An unknown error occurred",
                description: "An error occurred writing oppty to _TGT",
                // update as needed depending on retryable error types
                isRetryable: (retryableTypes contains item.upsertOpptyError.statusCode) default false,
                maxRetries: Mule::p("errHsptl.maxRetries") as Number default 5
            }
            // oppty products mirror failure
            else if (!isEmpty(item.upsertOpptyProductsError))
            {
                errorType: (item.upsertOpptyProductsError.statusCode default [] joinBy "; ") default "UNKNOWN_ERROR",
                errorMessage: (item.upsertOpptyProductsError.message default [] joinBy "; ") default "An unknown error occurred",
                description: "An error occurred writing oppty products to _TGT",
                // update as needed depending on retryable error types
                isRetryable: (retryableTypes contains item.upsertOpptyError.statusCode) default false,
                maxRetries: Mule::p("errHsptl.maxRetries") as Number default 5
            }
            // writeback oppty failure
            else if (!isEmpty(item.writebackOpptyError))
            {
                errorType: item.writebackOpptyError.statusCode default "UNKNOWN_ERROR",
                errorMessage: item.writebackOpptyError.message default "An unknown error occurred",
                description: "An error occurred writing oppty back to _SRC",
                // update as needed depending on retryable error types
                isRetryable: (retryableTypes contains item.upsertOpptyError.statusCode) default false,
                maxRetries: Mule::p("errHsptl.maxRetries") as Number default 5
            }
            // unknown error
            else 
            {
                errorType: "UNKNOWN_ERROR",
                errorMessage: "An unknown error occurred",
                description: "An unknown error occurred; please check logs for transaction Id",
                // update as needed depending on retryable error types
                isRetryable: (retryableTypes contains item.upsertOpptyError.statusCode) default false,
                maxRetries: Mule::p("errHsptl.maxRetries") as Number default 5
            }
    })

// refactor (can't use getLastException() in aggregator)
fun buildSendSystemErrorRecordsToErrHsptlRequest(records, transactionId) = 
    records default [] map ((item, index) -> do {
        var errorData = Batch::getLastException()
        ---
        {
            recordId: item.Id,
            transactionId: transactionId, 
            error: {
                errorType: errorData.errorType default "UNKNOWN_ERROR",
                errorMessage: errorData.errorMessage default "An unknown error occurred",
                description: "A system error occurred during batch processing",
                // update as needed depending on retryable error types
                isRetryable: (retryableTypes contains item.errorData.errorType) default false,
                maxRetries: Mule::p("errHsptl.maxRetries") as Number default 5
            }
        }
    })

fun buildDeleteRecordsFromErrHsptlRequest(records) =
    records.Id default [] distinctBy ((item) -> item) default []