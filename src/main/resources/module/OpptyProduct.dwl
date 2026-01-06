%dw 2.0
import mergeWith from dw::core::Objects
import * from module::CommonUtil

fun buildQueryOpptyProductFromSourceByOpptyId(ids) =
    {
        query: 'SELECT Id, Target_Oppty_Product_Id__c, PricebookEntryId, OpportunityId, UnitPrice, Quantity FROM OpportunityLineItem WHERE OpportunityId IN (' ++ generateIdInClause(ids) ++ ')',
        queryParams: ids default [] distinctBy ((item, index) -> item) default [] map ((item,index) -> {
            (('idArg') ++ index): item
        }) reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

fun buildQueryOpptyProductFromTargetByOpptyId(ids) =
    {
        query: 'SELECT Id, PricebookEntryId, OpportunityId, Opportunity.Acquisition_Oppty_Id__c FROM OpportunityLineItem WHERE OpportunityId IN (' ++ generateIdInClause(ids) ++ ')',
        queryParams: ids default [] distinctBy ((item, index) -> item) default [] map ((item,index) -> {
            (('idArg') ++ index): item
        }) reduce ((item, accumulator = {}) -> item ++ accumulator)
    }

fun getTargetOpptyProductsToCreate(data) =
    do {
        var targetOpptyProductIds = data.existingTargetOpptyProductRecords.Id default []
        var targetPbEntryIds = data.existingTargetOpptyProductRecords.PricebookEntryId default []
        ---
        data.sourceOpptyProductRecords default [] filter ((item, index) -> (!(targetOpptyProductIds contains item.Target_Oppty_Product_Id__c) and !(targetPbEntryIds contains getTargetPbEntryIdBySourcePbEntryId(item.PricebookEntryId))))
    }
//tbd
fun getTargetOpptyProductsToUpdate(data) =
    do {
        var sourceOpptyProductIds = data.sourceOpptyProductRecords.Target_Oppty_Product_Id__c default []
        var sourcePbEntryIds = data.sourceOpptyProductRecords.PricebookEntryId default []
        ---
        data.existingTargetOpptyProductRecords default [] filter ((item, index) -> ((sourceOpptyProductIds contains item.Id) or (sourcePbEntryIds contains getSourcePbEntryIdByTargetPbEntryId(item.PricebookEntryId))))
    }

fun transformTargetOpptyProductCreate(data, targetOpptyProductsToCreate) =
    targetOpptyProductsToCreate default [] map ((item, index) -> do {
        var transformedData = {
            OpportunityId: data.targetOpptyResponse.id,
            PricebookEntryId: getTargetPbEntryIdBySourcePbEntryId(item.PricebookEntryId),
            Quantity: item.Quantity,
            UnitPrice: item.UnitPrice,
            //additional fields can be added here
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
})

fun transformTargetOpptyProductUpdate(data, targetOpptyProductsToUpdate) =
    targetOpptyProductsToUpdate default [] map ((item, index) -> do {
        var transformedData = {
            Id: item.Id,
            Quantity: (data.sourceOpptyProductRecords filter (($.Target_Oppty_Product_Id__c == item.Id) or ($.PricebookEntryId == getSourcePbEntryIdByTargetPbEntryId(item.PricebookEntryId))))[0].Quantity,
            UnitPrice: (data.sourceOpptyProductRecords filter (($.Target_Oppty_Product_Id__c == item.Id) or ($.PricebookEntryId == getSourcePbEntryIdByTargetPbEntryId(item.PricebookEntryId))))[0].UnitPrice
            //additional fields can be added here
        }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
})

fun getTargetPbEntryIdBySourcePbEntryId(sourcePbEntryId) =
    if (sourcePbEntryId == Mule::p('source.pbEntryId.productA')) Mule::p('target.pbEntryId.productA')
    else if (sourcePbEntryId == Mule::p('source.pbEntryId.productB')) Mule::p('target.pbEntryId.productB')
    else if (sourcePbEntryId == Mule::p('source.pbEntryId.productC')) Mule::p('target.pbEntryId.productC')
     else if (sourcePbEntryId == Mule::p('source.pbEntryId.productD')) Mule::p('target.pbEntryId.productD')
    else null

fun getSourcePbEntryIdByTargetPbEntryId(targetPbEntryId) =
    if (targetPbEntryId == Mule::p('target.pbEntryId.productA')) Mule::p('source.pbEntryId.productA')
    else if (targetPbEntryId == Mule::p('target.pbEntryId.productB')) Mule::p('source.pbEntryId.productB')
    else if (targetPbEntryId == Mule::p('target.pbEntryId.productC')) Mule::p('source.pbEntryId.productC')
    else if (targetPbEntryId == Mule::p('target.pbEntryId.productD')) Mule::p('source.pbEntryId.productD')
    else null

fun transformWritebackSourceOpptyProduct(data) =
    data.sourceOpptyProductRecords default [] map ((item, index) -> do {
        var transformedData = {
            Id: item.Id,
            Target_Oppty_Product_Id__c: if (!isEmpty(item.Target_Oppty_Product_Id__c)) item.Target_Oppty_Product_Id__c
                else if (!isEmpty(data.targetOpptyProductResponses[index].id)) data.targetOpptyProductResponses[index].id
                else null
            }
        var fieldsToNull = buildFieldsToNull(transformedData)
        ---
        if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
        else transformedData
    })