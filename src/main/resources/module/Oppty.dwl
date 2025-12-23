%dw 2.0
import mergeWith from dw::core::Objects
import * from module::CommonUtil

fun buildQueryOpptyFromSourceByDate(fromLastRunDateTime, toLastRunDateTime) =
	{
		//adjust fields as needed
		query: "SELECT Id, Target_Oppty_Id__c, Account.Target_Acct_Id__c, CloseDate, Name, StageName FROM Opportunity WHERE Target_Mirror_Scope__c = true and ((Target_Ready_To_Mirror_Date_Time__c >= :watermarkLastRunDateTime and Target_Ready_To_Mirror_Date_Time__c < :watermarkCurrentRunDateTime) or Target_Mirror_Error__c != null)",
		queryParams: {
			watermarkLastRunDateTime: fromLastRunDateTime,
			watermarkCurrentRunDateTime: toLastRunDateTime
		}
	}

fun buildQueryOpptyFromSourceById(ids) =
	{
		//adjust fields as needed
		query: "SELECT Id, Target_Oppty_Id__c, Account.Target_Acct_Id__c, CloseDate, Name, StageName FROM Opportunity WHERE ID IN (" ++ generateIdInClause(ids) ++ ")",
		queryParams: ids default [] distinctBy ((item, index) -> item) default [] map ((item,index) -> {
			(("idArg") ++ index): item
		}) reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun buildQueryOpptyFromTargetByExternalId(ids) =
	{
		query: "SELECT Id, Acquisition_Oppty_Id__c FROM Opportunity WHERE Acquisition_Oppty_Id__c IN (" ++ generateIdInClause(ids) ++ ")",
		queryParams: ids default [] distinctBy ((item, index) -> item) default [] map ((item,index) -> {
			(("idArg") ++ index): item
		}) reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun transformTargetOpptyUpdate(data) =
	data default [] map ((item, index) -> do {
		var transformedData = {
			AccountId: item.Account.Target_Acct_Id__c,
			Acquisition_Oppty_Id__c: item.Id,
			CloseDate: if (!isEmpty(item.CloseDate)) item.CloseDate as Date { format: "yyyy-MM-dd" } else null,
			Id: (item.existingTargetOpptyRecords filter ($.Acquisition_Oppty_Id__c == item.Id))[0].Id,
			Name: if (!isEmpty(item.Name)) "SOURCE - " ++ item.Name else null,
			StageName: item.StageName
			//additional fields can be added here
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformTargetOpptyCreate(data) =
	data default [] map ((item, index) -> do {
		var transformedData = {
			AccountId: item.Account.Target_Acct_Id__c,
			Acquisition_Oppty_Id__c: item.Id,
			CloseDate: if (!isEmpty(item.CloseDate)) item.CloseDate as Date { format: "yyyy-MM-dd" } else null,
			Name: if (!isEmpty(item.Name)) "SOURCE - " ++ item.Name else null,
			StageName: item.StageName
			//additional fields can be added here
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformWritebackSourceOppty(data) =
	data default [] map ((item, index) -> do {
		var transformedData = {
			Id: item.Id,
			Target_Oppty_Id__c: if (!isEmpty(item.Target_Oppty_Id__c)) item.Target_Oppty_Id__c
				else if (!isEmpty(item.targetOpptyResponse.id)) item.targetOpptyResponse.id
				else null,
			Target_Mirror_Error__c: if (!item.targetOpptyResponse.success) item.targetOpptyResponse.errors[0].message
				else if (item.targetOpptyProductResponses.success contains false) getTargetOpptyProductErrorMessages(item.targetOpptyProductResponses)
				else null
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
})