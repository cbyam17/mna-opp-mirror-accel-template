%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil

fun buildQueryOpptysByDate_SRC(fromLastRunDateTime, toLastRunDateTime) =
	{
		// adjust SOQL query per requirements
		query:	"SELECT Id, Oppty_Id_TGT__c, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
				"FROM Opportunity " ++
				"WHERE Mirror_Scope_TGT__c = true and ((TGT_Ready_To_Mirror_Date_Time__c >= :watermarkLastRunDateTime and TGT_Ready_To_Mirror_Date_Time__c < :watermarkCurrentRunDateTime) or Mirror_Error_TGT__c != null)",
		queryParams: {
			watermarkLastRunDateTime: fromLastRunDateTime,
			watermarkCurrentRunDateTime: toLastRunDateTime
		}
	}

fun buildQueryOpptysById_SRC(ids) =
	{
		// adjust _TGT SOQL query per requirements
		query:	"SELECT Id, Oppty_Id_TGT__c, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
				"FROM Opportunity " ++
				"WHERE Id IN ('" ++ generateIdInClause(ids) ++ "')",
		queryParams: ids default [] distinctBy ((item) -> item) default []
			map ((item,index) -> {
				(("idArg") ++ index): item
		}) reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun buildQueryOpptysByExternalId_TGT(externalIds) =
	{
		// adjust _TGT SOQL query per reqs
		query: 	"SELECT Id, Oppty_Id_SRC__c " ++
				"FROM Opportunity " ++
				"WHERE Oppty_Id_SRC__c IN ('" ++ generateIdInClause(externalIds) ++ "')",
		queryParams: externalIds default [] distinctBy ((item) -> item) default []
			map ((item,index) -> {
				(("idArg") ++ index): item
			})
			reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun transformCreateOpptys_TGT(records) =
	records default [] map ((item) -> do {
		var transformedData = {
			// adjust _TGT oppty field mapping per reqs
			AccountId: item.Account.Acct_Id_TGT__c,
			Oppty_Id_SRC__c: item.Id,
			CloseDate: if (!isEmpty(item.CloseDate)) item.CloseDate as Date { format: 'yyyy-MM-dd' } else null,
			Name: if (!isEmpty(item.Name)) 'SOURCE - ' ++ item.Name else null,
			StageName: item.StageName
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformUpdateOpptys_TGT(records) =
	records default [] map ((item) -> do {
		var transformedData = {
			// adjust _TGT opptty field mapping per reqs
			AccountId: item.Account.Acct_Id_TGT__c,
			Oppty_Id_SRC__c: item.Id,
			CloseDate: if (!isEmpty(item.CloseDate)) item.CloseDate as Date { format: 'yyyy-MM-dd' } else null,
			Id: item.existingOpptyId,
			Name: if (!isEmpty(item.Name)) 'SOURCE - ' ++ item.Name else null,
			StageName: item.StageName		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformWritebackSourceOpptys_SRC(records) =
	records default [] map ((item) -> do {
		var transformedData = {
			// adjust _SRC oppty field mapping per reqs
			Id: item.Id,
			Oppty_Id_TGT__c: if (!isEmpty(item.existingOpptyId)) item.existingOpptyId
				else if (!isEmpty(item.upsertedOpptyId)) item.upsertedOpptyId
				else null,
			Mirror_Error_TGT__c: if (!isEmpty(item.upsertOpptyError)) buildErrorMessage("Opportunity", item.upsertOpptyError.message)
				else if (!isEmpty(item.upsertOpptyProductErrors)) buildErrorMessage("OpportunityLineItem", (item.upsertOpptyProductErrors.message default [] joinBy "; "))
				else null
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun buildErrorMessage(objectType, message) =
	"_TGT mirror error - " ++ objectType default "" ++ ": " ++ message default "Unknown error"