%dw 2.0

fun transformExistingErrHsptlRecordsMap(records, existingErrHsptlRecords) =
    records filter ((item) -> (existingErrHsptlRecords.recordId contains item.Id))
        map ((item) -> {
            key: item.Id,
            value: true
        })

// logic TBD
fun transformExistingOpptysMap(records, existingOpptys) =
    records filter ((item) -> (existingOpptys.Oppty_Id_SRC__c contains item.Id))
        map ((item) -> {
            key: item.Id,
            value: true
        })

fun transformCreateOpptysResponseMap(records, createOpptysResponse) =
    (records zip createOpptysResponse)
        map ((pair) -> {
            key: pair[0].Id,
            value: pair[1]
        })

fun transformUpdateOpptysResponseMap(records, updateOpptysResponse) =
    (records zip updateOpptysResponse)
        map ((pair) -> {
            key: pair[0].Id,
            value: pair[1]
        })

fun transformOpptyProductsMap(records, opptyProducts) =
    records map (item) -> {
        key: item.Id,
        value: opptyProducts filter ((op) -> (op.OpportunityId == item.Id))
    }

fun transformExistingOpptyProductsMap(records, existingOpptyProducts) =
    records map (item) -> {
        key: item.existingOpptyId,
        value: existingOpptyProducts filter ((op) -> (op.OpportunityId == item.existingOpptyId))
    }

fun transformCreateOpptyProductsResponseMap(records, createOpptyProductsResponse) =
    (flatten(records.opptyProductsToCreate) zip createOpptyProductsResponse)
        map ((pair) -> {
            opptyId: pair[0].OpportunityId,
            upsertedOpptyProductId: pair[1].id,
            upsertOpptyProductError: pair[1].errors[0]
        })
        groupBy ((r) -> r.opptyId)
        pluck (v, k) -> {
            key: k,
            value: v
        }

fun transformUpdateOpptyProductsResponseMap(records, updateOpptyProductsResponse) =
    (flatten(records.opptyProductsToUpdate) zip updateOpptyProductsResponse)
        map ((pair) -> {
            opptyId: pair[0].Opportunity.Oppty_Id_SRC__c,
            upsertedOpptyProductId: pair[1].id,
            upsertOpptyProductError: pair[1].errors[0]
        })
        groupBy ((r) -> r.opptyId)
        pluck (v, k) -> {
            key: k,
            value: v
        }

fun transformWritebackOpptysResponseMap(records, writebackOpptysResponse) =
    (records zip writebackOpptysResponse)
        map ((pair) -> {
            key: pair[0].Id,
            value: pair[1]
        })