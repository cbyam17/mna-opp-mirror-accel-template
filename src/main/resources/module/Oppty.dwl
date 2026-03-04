%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil
import mapPbEntryId from module::OpptyProduct

fun buildQueryOpptysByDate_SRC(fromLastRunDateTime, toLastRunDateTime) =
	{
		// adjust SOQL query per requirements
		query:	"SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName FROM Opportunity WHERE Mirror_Scope_TGT__c = true and ((TGT_Ready_To_Mirror_Date_Time__c >= :watermarkLastRunDateTime and TGT_Ready_To_Mirror_Date_Time__c < :watermarkCurrentRunDateTime) or Mirror_Error_TGT__c != null)",
		queryParams: {
			watermarkLastRunDateTime: fromLastRunDateTime,
			watermarkCurrentRunDateTime: toLastRunDateTime
		}
	}

fun buildQueryOpptysById_SRC(ids) =
	{
		// adjust _TGT SOQL query per requirements
		query:	"SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName FROM Opportunity WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",
		queryParams: ids default [] distinctBy ((item) -> item) default []
			map ((item,index) -> {
				(("idArg") ++ index): item
		}) reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun buildQueryOpptysByExternalId_TGT(externalIds) =
	{
		// adjust _TGT SOQL query per reqs
		query: 	"SELECT Id, Oppty_Id_SRC__c FROM Opportunity WHERE Oppty_Id_SRC__c IN (" ++ generateIdInClause(externalIds) ++ ")",
		queryParams: externalIds default [] distinctBy ((item) -> item) default []
			map ((item,index) -> {
				(("idArg") ++ index): item
			})
			reduce ((item, accumulator = {}) -> item ++ accumulator)
	}

fun enrichOpptysWithQueryResults(records, existingAccts, existingOpptys, existingErrHsptlRecords, existingOpptyProducts, opptyProducts) =
	//existingAccts contains accts queried from TGT
	//existingOpptys contains opptys queried from TGT
	//existingErrHsptlRecords contains records fetched from error hospital
	//existingOpptyProducts contains oppty products queried from TGT
	//opptyProducts contains oppty products queried from SRC
	records default [] map ((item) -> item ++ 
		do {
			var recExistingAcct = (existingAccts default [] filter ((a) -> (a.Id == item.Account.Acct_Id_TGT__c)))[0]
			var recExistingOppty = (existingOpptys default [] filter ((o) -> (o.Oppty_Id_SRC__c == item.Id)))[0]
			var recExistingErrHsptlRecord = (existingErrHsptlRecords default [] filter ((e) -> (e.recordId == item.id)))[0]
			// compares _SRC vs _TGT pb entry ids to determine which oppty product records to create and which to update in TGT
			var recExistingOpptyProducts = (existingOpptyProducts default []) filter ((op) -> 
				(op.Opportunity.Oppty_Id_SRC__c == item.Id))
			var recOpptyProducts = (opptyProducts default []) filter ((op) -> 
				(op.OpportunityId == item.Id))
        	var recOpptyProductsToCreate = (recOpptyProducts default []) filter ((item) -> 
				(!(recExistingOpptyProducts.PricebookEntryId default [] contains mapPbEntryId(item.PricebookEntryId,"_TGT"))))
        	var recOpptyProductsToUpdate = (recExistingOpptyProducts default []) filter ((item) -> 
				(recOpptyProducts.PricebookEntryId default [] contains mapPbEntryId(item.PricebookEntryId,"_SRC")))
			var recOpptyProductsToDelete = (recExistingOpptyProducts default []) filter ((e) -> 
				!((((recOpptyProducts default []) map ($.Id as String)) contains (e.Oppty_Product_Id_SRC__c as String)))
  )
        	---
			{
				existingAcct: recExistingAcct default null,
				existingOppty: recExistingOppty default null,
				existingErrHsptlRecord: recExistingErrHsptlRecord default null,
				existingOpptyProducts: recExistingOpptyProducts default [],
				opptyProducts: recOpptyProducts default [],
				opptyProductsToCreate: recOpptyProductsToCreate default [],
				opptyProductsToUpdate: recOpptyProductsToUpdate default [],
				opptyProductsToDelete: recOpptyProductsToDelete default []
			}
		}
	)

fun transformCreateOppty_TGT(records) =
	records default [] map ((item) -> do {
		var transformedData = transformOppty_TGT(item)
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformUpdateOppty_TGT(records) =
	records default [] map ((item) -> do {
		var transformedData = transformOppty_TGT(item) ++ {
			Id: item.existingOppty.Id
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun transformOppty_TGT(record) =
	// record.existingAcct contains acct queried from TGT
	{
		// adjust _TGT opptty field mapping per reqs
		AccountId: record.Account.Acct_Id_TGT__c,
		Oppty_Id_SRC__c: record.Id,
		OwnerId: record.existingAcct.OwnerId,
		CloseDate: if (!isEmpty(record.CloseDate)) record.CloseDate as Date { format: 'yyyy-MM-dd' } else null,
		Name: if (!isEmpty(record.Name)) 'SRC - ' ++ record.Name else null,
		StageName: record.StageName		
	}

fun transformWritebackOppty_SRC(records) =
	// item.existingOppty contains oppty queried from TGT
	// item.upsertOpptyResponse contains response from oppty upsert in TGT
	// item.upsertOpptyProductResponses contains responses from oppty product upserts in TGT
	records default [] map ((item) -> do {
		var transformedData = {
			// adjust _SRC oppty field mapping per reqs
			Id: item.Id,
			Oppty_Id_TGT__c: if (!isEmpty(item.existingOppty)) item.existingOppty.Id
				else if (item.upsertOpptyResponse.success == true) item.upsertOpptyResponse.id
				else null,
			Mirror_Error_TGT__c: if (item.upsertOpptyResponse.success == false) buildErrorMessage("Opportunity", item.upsertOpptyResponse.errors[0].message)
				else if (item.upsertOpptyProductResponses.success contains false) buildErrorMessage("OpportunityLineItem", (item.upsertOpptyProductResponses.errors[0].message default [] joinBy "; "))
				else null
		}
		var fieldsToNull = buildFieldsToNull(transformedData)
		---
		if (!isEmpty(fieldsToNull)) transformedData mergeWith { fieldsToNull: fieldsToNull } 
		else transformedData
	})

fun buildErrorMessage(objectType, message) =
	"_TGT mirror error - " ++ objectType default "" ++ ": " ++ message default "Unknown error"