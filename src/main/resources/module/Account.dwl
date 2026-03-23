// ============================================================================
// Account Module DataWeave
// ============================================================================

%dw 2.0
import generateIdInClause from module::CommonUtils

// Adjust SOQL query as needed
fun buildQueryAcctsById_TGT(ids) =
  {
    query:
      "SELECT Id, OwnerId " ++
      "FROM Account WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",
    queryParams:
      (ids default [])
        distinctBy ($)
          map ((item, index) -> { (("idArg") ++ index): item })
            reduce ((acc = {}, item) -> acc ++ item)
  }