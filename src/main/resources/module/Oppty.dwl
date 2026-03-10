%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil
import mapPbEntryId from module::OpptyProduct

// -----------------------------------------------------------------------------
// Utility helpers
// -----------------------------------------------------------------------------

// Normalize to array to avoid scalar/array branching later
fun toArray(v) =
  if (v is Array) v
  else if (v == null) []
  else [v]

// Safe-filter-then-first pattern
fun firstOrNull(arr) = ((arr default []) as Array)[0] default null

// -----------------------------------------------------------------------------
// SOQL builders
// -----------------------------------------------------------------------------

/**
 * Build a SOQL query to fetch Opportunities (SRC) by watermark window.
 * Note: uses bind variables (queryParams) for runtime values.
 */
fun buildQueryOpptysByDate_SRC(fromLastRunDateTime, toLastRunDateTime) =
  {
    query:
      "SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
      "FROM Opportunity " ++
      "WHERE Mirror_Scope_TGT__c = true AND " ++
      "((TGT_Ready_To_Mirror_Date_Time__c >= :watermarkLastRunDateTime " ++
      "AND TGT_Ready_To_Mirror_Date_Time__c < :watermarkCurrentRunDateTime) " ++
      "OR Mirror_Error_TGT__c != null)",
    queryParams: {
      watermarkLastRunDateTime: fromLastRunDateTime,
      watermarkCurrentRunDateTime: toLastRunDateTime
    }
  }

/**
 * Build a SOQL query to fetch Opportunities (SRC) by Id list.
 * De-dupes ids and passes them as named parameters idArg0, idArg1, ...
 */
fun buildQueryOpptysById_SRC(ids) =
  {
    query:
      "SELECT Id, Account.Acct_Id_TGT__c, CloseDate, Name, StageName " ++
      "FROM Opportunity WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",
    queryParams:
      (ids default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        // reduce with (acc, item) signature (avoid parameter confusion)
        reduce ((acc = {}, item) -> acc ++ item)
  }

/**
 * Build a SOQL query to fetch Opportunities (TGT) by external id(s).
 * De-dupes externalIds and passes them as named parameters idArg0, idArg1, ...
 */
fun buildQueryOpptysByExternalId_TGT(externalIds) =
  {
    query:
      "SELECT Id, Oppty_Id_SRC__c " ++
      "FROM Opportunity WHERE Oppty_Id_SRC__c IN (" ++ generateIdInClause(externalIds) ++ ")",
    queryParams:
      (externalIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((acc = {}, item) -> acc ++ item)
  }

// -----------------------------------------------------------------------------
// Enrichment: add related records + compute product create/update/delete sets
// -----------------------------------------------------------------------------

/**
 * Enrich Opportunities with:
 *  - existing TGT account/oppty, existing error hospital record
 *  - TGT/SRC OLI partitions for this opportunity
 *  - Delta sets for OLI create/update/delete in TGT
 *
 * Assumptions:
 *  - existingOpptyProducts: array of TGT OLIs with fields .PricebookEntryId and .Opportunity.Oppty_Id_SRC__c
 *  - opptyProducts: array of SRC OLIs with fields .PricebookEntryId and .OpportunityId
 *  - mapPbEntryId(value, "_TGT" | "_SRC") maps PricebookEntryId across systems
 */
fun enrichOpptysWithQueryResults(
  records,
  existingAccts,
  existingOpptys,
  existingErrHsptlRecords,
  existingOpptyProducts,
  opptyProducts
) =
  (records default []) map ((r) -> do {
      // Lookups in TGT / error hospital
      var recExistingAcct =
        firstOrNull((existingAccts default []) filter ((a) -> a.Id == r.Account.Acct_Id_TGT__c))

      var recExistingOppty =
        firstOrNull((existingOpptys default []) filter ((o) -> o.Oppty_Id_SRC__c == r.Id))

      var recExistingErrHsptlRecord =
        firstOrNull((existingErrHsptlRecords default []) filter ((e) -> e.recordId == r.Id))

      // Partition OLIs by opportunity (SRC vs TGT)
      var recExistingOpptyProducts =
        (existingOpptyProducts default []) filter ((o) -> o.Opportunity.Oppty_Id_SRC__c == r.Id)

      var recOpptyProducts =
        (opptyProducts default []) filter ((op) -> op.OpportunityId == r.Id)

      // PricebookEntryId lists for membership checks
      var tgtPbeIds = (recExistingOpptyProducts default []) map ((pbe) -> pbe.PricebookEntryId)
      var srcPbeIds = (recOpptyProducts default []) map ((pbe) -> pbe.PricebookEntryId)

      // CREATE in TGT: SRC OLI whose mapped TGT PBE isn't present in TGT
      var recOpptyProductsToCreate =
        (recOpptyProducts default [])
          filter ((op) -> !(tgtPbeIds contains mapPbEntryId(op.PricebookEntryId, "_TGT")))

      // UPDATE in TGT: TGT OLI whose mapped SRC PBE exists in SRC
      var recOpptyProductsToUpdate =
        (recExistingOpptyProducts default [])
          filter ((op) -> (srcPbeIds contains mapPbEntryId(op.PricebookEntryId, "_SRC")))

      // DELETE in TGT: TGT OLI whose mapped TGT PBE doesn't exist in current SRC set
      var recOpptyProductsToDelete =
        (recExistingOpptyProducts default [])
          filter ((op) -> !(srcPbeIds contains mapPbEntryId(op.PricebookEntryId, "_SRC")))
      ---
      r ++ {
        existingAcct:           recExistingAcct default null,
        existingOppty:          recExistingOppty default null,
        existingErrHsptlRecord: recExistingErrHsptlRecord default null,
        existingOpptyProducts:  recExistingOpptyProducts default [],
        opptyProducts:          recOpptyProducts default [],
        opptyProductsToCreate:  recOpptyProductsToCreate default [],
        opptyProductsToUpdate:  recOpptyProductsToUpdate default [],
        opptyProductsToDelete:  recOpptyProductsToDelete default []
      }
    }
  )

// -----------------------------------------------------------------------------
// Transformations for TGT Opportunity upsert
// -----------------------------------------------------------------------------

/**
 * Field mapping to TGT Opportunity (common for create/update).
 * Applies formatting and safe nulls.
 */
fun transformOppty_TGT(record) =
  {
    AccountId:       record.Account.Acct_Id_TGT__c,
    Oppty_Id_SRC__c: record.Id,
    OwnerId:         record.existingAcct.OwnerId,
    CloseDate:
      if (!isEmpty(record.CloseDate))
        record.CloseDate as Date { format: "yyyy-MM-dd" }
      else
        null,
    Name:
      if (!isEmpty(record.Name))
        "SRC - " ++ record.Name
      else
        null,
    StageName:       record.StageName
  }

/**
 * Map SRC Opportunity -> TGT (create).
 * Adds fieldsToNull when non-empty.
 */
fun transformCreateOppty_TGT(records) =
  (records default []) map ((r) -> do {
      var transformed = transformOppty_TGT(r)
      var fieldsToNull = buildFieldsToNull(transformed)
      ---
      if (!isEmpty(fieldsToNull))
        transformed mergeWith { fieldsToNull: fieldsToNull }
      else
        transformed
    }
  )

/**
 * Map SRC Opportunity -> TGT (update).
 * Requires r.existingOppty.Id (from TGT).
 */
fun transformUpdateOppty_TGT(records) =
  (records default [])
    map ((r) -> do {
      var transformed =
        transformOppty_TGT(r) ++ {
          Id: r.existingOppty.Id
        }
      var fieldsToNull = buildFieldsToNull(transformed)
      ---
      if (!isEmpty(fieldsToNull))
        transformed mergeWith { fieldsToNull: fieldsToNull }
      else
        transformed
    }
  )

// -----------------------------------------------------------------------------
// Write-back to SRC (mirror results & errors)
// -----------------------------------------------------------------------------

/**
 * Simple error formatter for write-back.
 */
fun buildErrorMessage(objectType, message) =
  "_TGT mirror error - " ++ (objectType default "") ++ ": " ++ (message default "Unknown error")

/**
 * Compute write-back payload for SRC Opportunity with TGT ids and any errors.
 * Determines TGT Id (existing or created) and composes a unified error message.
 */
fun transformWritebackOppty_SRC(records) =
  (records default []) map ((r) ->
    do {
      var tgtOpptyId =
        if (!isEmpty(r.existingOppty))
          r.existingOppty.Id
        else if ((r.createOpptyResponse.success default false) == true)
          r.createOpptyResponse.id
        else
          null

      // Derive a unified error string, prioritizing create/update OLI errors last.
      var tgtMirrorError =
        if ((r.createOpptyResponse.success default true) == false)
          buildErrorMessage("Opportunity", r.createOpptyResponse.errors[0].message)
        else if ((r.updateOpptyResponse.success default true) == false)
          buildErrorMessage("Opportunity", r.updateOpptyResponse.errors[0].message)
        else if (((toArray(r.createOpptyProductResponses)).success default []) contains false)
          buildErrorMessage("OpportunityLineItem", ((toArray(r.createOpptyProductResponses))..errors[0].message default []) joinBy "; ")
        else if (((toArray(r.updateOpptyProductResponses)).success default []) contains false)
          buildErrorMessage("OpportunityLineItem", ((toArray(r.updateOpptyProductResponses))..errors[0].message default []) joinBy "; ")
        else if (((toArray(r.deleteOpptyProductResponses)).success default []) contains false)
          buildErrorMessage("OpportunityLineItem", ((toArray(r.deleteOpptyProductResponses))..errors[0].message default []) joinBy "; ")
        else if ((r.isSystemError default false) == true)
          buildErrorMessage("Opportunity", Mule::p("error.defaultDescription") as String)
        else
          null

      var transformed =
        {
          Id: r.Id,
          Oppty_Id_TGT__c: tgtOpptyId,
          Mirror_Error_TGT__c: tgtMirrorError
        }

      var fieldsToNull = buildFieldsToNull(transformed)
      ---
      if (!isEmpty(fieldsToNull))
        transformed mergeWith { fieldsToNull: fieldsToNull }
      else
        transformed
    }
  )