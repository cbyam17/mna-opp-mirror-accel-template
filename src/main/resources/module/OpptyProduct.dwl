%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil

fun buildQueryOpptyProductsByOpptyId_SRC(opptyIds) =
    {
    	// adjust SOQL query per reqs
        query: "SELECT Id, Oppty_Product_Id_TGT__c, PricebookEntryId, OpportunityId, UnitPrice, Quantity FROM OpportunityLineItem WHERE OpportunityId IN (" ++ generateIdInClause(opptyIds) ++ ")",
        queryParams: opptyIds default [] distinctBy ((item) -> item) default []
            map ((item,index) -> {
                (("idArg") ++ index): item
            })
            reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

fun buildQueryOpptyProductsByOpptyExternalId_TGT(opptyIds) =
    {
        // adjust SOQL query per reqs
        query: "SELECT Id, Oppty_Product_Id_SRC__c, PricebookEntryId, OpportunityId, Opportunity.Oppty_Id_SRC__c FROM OpportunityLineItem WHERE Opportunity.Oppty_Id_SRC__c IN (" ++ generateIdInClause(opptyIds) ++ ")",
        queryParams: opptyIds default [] distinctBy ((item) -> item) default []
            map ((item,index) -> {
                (("idArg") ++ index): item
            })
            reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

fun transformCreateOpptyProducts_TGT(record) = 
    // record.opptyProductsToCreate contains oppty products queried from SRC that do not exist in TGT
    // record.upsertOpptyResponses contains responses from oppty product upserts in TGT
    record.opptyProductsToCreate default [] map ((item) -> do {
        // adjust fields as needed
        var transformedData = {
            OpportunityId: record.upsertOpptyResponse.id,
            PricebookEntryId: mapPbEntryId(item.PricebookEntryId, "_TGT"),
            Quantity: item.Quantity default 0 as Number,
            UnitPrice: item.UnitPrice default 0 as Number,
            Oppty_Product_Id_SRC__c: item.Id
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
    })

fun transformUpdateOpptyProducts_TGT(record) =
    // record.opptyProductsToUpdate contains oppty products queried from TGT that match oppty products queried from SRC
    // record.opptyProducts contains oppty products queried from SRC
    record.opptyProductsToUpdate default [] map ((item) -> do {
        var transformedData = {
        	// adjust fields as needed
            Id: item.Id,
            Quantity: (record.opptyProducts filter ((op) -> (mapPbEntryId(op.PricebookEntryId,"_TGT") == item.PricebookEntryId)))[0].Quantity default 0 as Number,
            UnitPrice: (record.opptyProducts filter ((op) -> (mapPbEntryId(op.PricebookEntryId,"_TGT") == item.PricebookEntryId)))[0].UnitPrice default 0 as Number,
            Oppty_Product_Id_SRC__c: (record.opptyProducts filter ((op) -> (mapPbEntryId(op.PricebookEntryId,"_TGT") == item.PricebookEntryId)))[0].Id
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
     })

fun transformDeleteOpptyProducts_TGT(record) =
    record.opptyProductsToDelete.Id default []

fun transformWritebackOpptyProducts_SRC(record) =
    // record.opptyProducts contains oppty products queried from SRC
    // record.existingOpptyProducts contains oppty products queried from TGT
    // record.upsertOpptyResponses contains responses from oppty product upsert in TGT
    record.opptyProducts default [] map ((item) -> do {
        var isExistingOpptyProduct = record.existingOpptyProducts.Oppty_Product_Id_SRC__c contains item.Id
        // adjust fields as needed
        var transformedData = {
            Id: item.Id,
            // Id of matching existing TGT oppty product or Id of matching upserted TGT oppty product
            Oppty_Product_Id_TGT__c: if (isExistingOpptyProduct) (record.existingOpptyProducts filter ((op) -> (op.Oppty_Product_Id_SRC__c == item.Id)))[0].Id
                else (record.upsertOpptyProductResponses filter ((op) -> (op.srcId == item.Id)))[0].id
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
    })

// adjust PB entry Ids depending on the fixed PB entries mapping
fun mapPbEntryId(pbEntryId, destination) =
	if (destination == "_TGT")
	    if (pbEntryId == Mule::p('src.pbEntryId.C')) Mule::p('tgt.pbEntryId.C')
	    else if (pbEntryId == Mule::p('src.pbEntryId.OT')) Mule::p('tgt.pbEntryId.OT')
	    else if (pbEntryId == Mule::p('src.pbEntryId.OG')) Mule::p('tgt.pbEntryId.OG')
	    else null
	else if (destination == "_SRC")
		if (pbEntryId == Mule::p('tgt.pbEntryId.C')) Mule::p('src.pbEntryId.C')
	    else if (pbEntryId == Mule::p('tgt.pbEntryId.OT')) Mule::p('src.pbEntryId.OT')
	    else if (pbEntryId == Mule::p('tgt.pbEntryId.OG')) Mule::p('src.pbEntryId.OG')
	    else null
	else null    
