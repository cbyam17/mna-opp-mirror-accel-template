%dw 2.0
import mergeWith from dw::core::Objects
import generateIdInClause, buildFieldsToNull from module::CommonUtil

// -----------------------------------------------------------------------------
// SOQL builders
// -----------------------------------------------------------------------------

/**
 * Build a SOQL query (SRC) to fetch OpportunityLineItems by OpportunityId list.
 * @param opptyIds Array<String>
 */
fun buildQueryOpptyProductsByOpptyId_SRC(opptyIds) =
  {
    // Adjust SOQL per requirements
    query:
      "SELECT Id, PricebookEntryId, OpportunityId, UnitPrice, Quantity " ++
      "FROM OpportunityLineItem WHERE OpportunityId IN (" ++ generateIdInClause(opptyIds) ++ ")",

    queryParams:
      (opptyIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((item, acc = {}) -> acc ++ item)
  }

/**
 * Build a SOQL query (TGT) to fetch OLI by Opportunity external id (Oppty_Id_SRC__c).
 * @param opptyIds Array<String>  // These are the source Opportunity Ids
 */
fun buildQueryOpptyProductsByOpptyExternalId_TGT(opptyIds) =
  {
    // Adjust SOQL per requirements
    query:
      "SELECT Id, PricebookEntryId, OpportunityId, Opportunity.Oppty_Id_SRC__c " ++
      "FROM OpportunityLineItem " ++
      "WHERE Opportunity.Oppty_Id_SRC__c IN (" ++ generateIdInClause(opptyIds) ++ ")",

    queryParams:
      (opptyIds default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((item, acc = {}) -> acc ++ item)
  }

// -----------------------------------------------------------------------------
// TGT create/update/delete payloads
// -----------------------------------------------------------------------------

/**
 * Create payloads for TGT OLIs based on SRC create set.
 * expects:
 *  - record.opptyProductsToCreate        : Array<SRC OLI>
 *  - record.upsertOpptyResponse          : { id, success, errors }
 */
fun transformCreateOpptyProducts_TGT(records) =
  (records default []) flatMap ((r) ->
    (r.opptyProductsToCreate default []) map ((op) -> do {
      // Adjust field mapping as needed
      var transformedData =
        {
          OpportunityId:               r.upsertOpptyResponse.id,
          PricebookEntryId:            mapPbEntryId(op.PricebookEntryId, "_TGT"),
          Quantity:                    ((op.Quantity  default 0) as Number),
          UnitPrice:                   ((op.UnitPrice default 0) as Number),
          Oppty_Product_Id_SRC__c:     op.Id
        }
      var fieldsToNull = buildFieldsToNull(transformedData)
      ---
      if (!isEmpty(fieldsToNull))
        transformedData mergeWith { fieldsToNull: fieldsToNull }
      else
        transformedData
    })
  )

/**
 * Update payloads for TGT OLIs based on matched SRC lines.
 * expects:
 *  - record.opptyProductsToUpdate        : Array<TGT OLI>
 *  - record.opptyProducts                : Array<SRC OLI>
 *
 * Matching rule:
 *  - Find the SRC OLI whose mapped TGT PBE equals the TGT OLI PBE.
 */
fun transformUpdateOpptyProducts_TGT(records) =
  (records default []) flatMap ((r) ->
    (r.opptyProductsToUpdate default []) map ((op) -> do {
      var matchSrc =
        ((r.opptyProducts default [])
          filter ((item) -> mapPbEntryId(item.PricebookEntryId, "_TGT") == op.PricebookEntryId))[0]

      var transformedData =
        {
          Id:                          op.Id,
          Quantity:                    ((matchSrc.Quantity  default 0) as Number),
          UnitPrice:                   ((matchSrc.UnitPrice default 0) as Number)
        }

      var fieldsToNull = buildFieldsToNull(transformedData)
      ---
      if (!isEmpty(fieldsToNull))
        transformedData mergeWith { fieldsToNull: fieldsToNull }
      else
        transformedData
    })
  )

/**
 * Delete list for TGT OLIs.
 * expects:
 *  - record.opptyProductsToDelete        : Array<TGT OLI>
 * @return Array<String> of Ids to delete
 */
fun transformDeleteOpptyProducts_TGT(records) =
  (records default []) flatMap ((r) ->
    (r.opptyProductsToDelete default []) map ((op) -> op.Id)
  )

// -----------------------------------------------------------------------------
// PBE mapping helper
// -----------------------------------------------------------------------------

/**
 * Map PB Entry Ids between SRC and TGT by fixed property mapping.
 * destination: "_TGT" | "_SRC"
 */
fun mapPbEntryId(pbEntryId, destination) =
  if (destination == "_TGT")
    if      (pbEntryId == Mule::p("src.pbEntryId.C"))  Mule::p("tgt.pbEntryId.C")
    else if (pbEntryId == Mule::p("src.pbEntryId.OT")) Mule::p("tgt.pbEntryId.OT")
    else if (pbEntryId == Mule::p("src.pbEntryId.OG")) Mule::p("tgt.pbEntryId.OG")
    else if (pbEntryId == Mule::p("src.pbEntryId.DT")) Mule::p("tgt.pbEntryId.DT")
    else null
  else if (destination == "_SRC")
    if      (pbEntryId == Mule::p("tgt.pbEntryId.C"))  Mule::p("src.pbEntryId.C")
    else if (pbEntryId == Mule::p("tgt.pbEntryId.OT")) Mule::p("src.pbEntryId.OT")
    else if (pbEntryId == Mule::p("tgt.pbEntryId.OG")) Mule::p("src.pbEntryId.OG")
    else if (pbEntryId == Mule::p("tgt.pbEntryId.DT")) Mule::p("src.pbEntryId.DT")
    else null
  else null