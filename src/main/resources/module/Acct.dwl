%dw 2.0
import generateIdInClause from module::CommonUtil

// -----------------------------------------------------------------------------
// SOQL builder(s)
// -----------------------------------------------------------------------------

/**
 * Build a SOQL query to fetch Accounts (TGT) by Id list.
 * @param ids Array<String>
 */
fun buildQueryAcctsById_TGT(ids) =
  {
    // Adjust _TGT SOQL query per requirements
    query:
      "SELECT Id, OwnerId " ++
      "FROM Account WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",

    queryParams:
      (ids default [])
        distinctBy ($)
        map ((item, index) -> { (("idArg") ++ index): item })
        reduce ((item, acc = {}) -> acc ++ item)
  }