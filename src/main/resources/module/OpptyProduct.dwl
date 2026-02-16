%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil

fun buildQueryOpptyProductsByOpptyId_SRC(opptyIds) =
    {
    	// adjust SOQL query per reqs
        query: 'SELECT Id, PricebookEntryId, OpportunityId FROM OpportunityLineItem WHERE OpportunityId IN (' ++ generateIdInClause(opptyIds) ++ ')',
        queryParams: opptyIds default [] distinctBy ((item) -> item) default []
            map ((item,index) -> {
                (('idArg') ++ index): item
            })
            reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

fun buildQueryOpptyProductsByOpptyId_TGT(opptyIds) =
    {
        // adjust SOQL query per reqs
        query: 'SELECT Id, PricebookEntryId, OpportunityId, Opportunity.Oppty_Id_SRC__c FROM OpportunityLineItem WHERE OpportunityId IN (' ++ generateIdInClause(opptyIds) ++ ')',
        queryParams: opptyIds default [] distinctBy ((item) -> item) default []
            map ((item,index) -> {
                (('idArg') ++ index): item
            })
            reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

// fn that compares _SRC vs _TGT pb entry ids to determine which oppty product records to create and which to update
fun transformOpptyProductsToUpsert_TGT(record, opptyProducts, existingOpptyProducts) =
    do {
        var existingPbEntryIds = existingOpptyProducts.PriceookEntryId default []
        var pbEntryIds = opptyProducts.PriceookEntryId default []
        var opptyProductsToCreate = opptyProducts default [] filter ((item) -> (!(existingPbEntryIds contains mapPbEntryId(item.PriceookEntryId,"_TGT"))))
        var opptyProductsToUpdate = existingOpptyProducts default [] filter ((item) -> (pbEntryIds contains mapPbEntryId(item.PriceookEntryId,"_SRC")))
        ---
        record ++ {
            opptyProductsToCreate: opptyProductsToCreate default [],
            opptyProductsToUpdate: opptyProductsToUpdate default []
        }
    }

fun transformCreateOpptyProducts_TGT(records) =
    flatten(records.opptyProductsToCreate) default [] map ((item) -> do {
        var transformedData = {
        	// adjust fields as needed
            OpportunityId: (records filter ((r) -> (r.Id == item.OpportunityId))).upsertedOpptyId,
            PricebookEntryId: mapPbEntryId(item.PricebookEntryId, "_TGT"),
            Quantity: item.Quantity default 0 as Number,
            UnitPrice: item.UnitPrice default 0 as Number
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
    })

fun transformUpdateOpptyProducts_TGT(records) =
    flatten(records.opptyProductsToUpdate) default [] map ((item) -> do {
        var transformedData = {
        	// adjust fields as needed
            Id: item.Id,
            Quantity: (records filter ((r) -> (r.Id == item.Oppty_Id_SRC__c))).Quantity default 0 as Number,
            UnitPrice: (records filter ((r) -> (r.Id == item.Oppty_Id_SRC__c))).UnitPrice default 0 as Number
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
     })

// adjust PB entry Ids depending on the fixed PB entries mapping
fun mapPbEntryId(pbEntryId, destination) =
	if (destination == "_TGT")
	    if (pbEntryId == Mule::p('src.pbEntryId.productA')) Mule::p('tgt.pbEntryId.productA')
	    else if (pbEntryId == Mule::p('src.pbEntryId.productB')) Mule::p('tgt.pbEntryId.productB')
	    else if (pbEntryId == Mule::p('src.pbEntryId.productC')) Mule::p('tgt.pbEntryId.productC')
	    else if (pbEntryId == Mule::p('src.pbEntryId.productD')) Mule::p('tgt.pbEntryId.productD')
	    else null
	else if (destination == "_SRC")
		if (pbEntryId == Mule::p('tgt.pbEntryId.productA')) Mule::p('src.pbEntryId.productA')
	    else if (pbEntryId == Mule::p('tgt.pbEntryId.productB')) Mule::p('src.pbEntryId.productB')
	    else if (pbEntryId == Mule::p('tgt.pbEntryId.productC')) Mule::p('src.pbEntryId.productC')
	    else if (pbEntryId == Mule::p('tgt.pbEntryId.productD')) Mule::p('src.pbEntryId.productD')
	    else null
	else null    
