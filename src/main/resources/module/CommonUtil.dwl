%dw 2.0

// -----------------------------------------------------------------------------
// Health/Ping helpers
// -----------------------------------------------------------------------------

/**
 * Build a single endpoint ping response.
 * @param name      String
 * @param response  Object (expects errorType?, description?)
 * @return Array<Object> with one element to make aggregation trivial
 */
fun buildPingEndpointResponse(name, response) =
  [
    {
      name:    name,
      status:  if (isEmpty(response.errorType)) "UP" else "DOWN",
      message: if (isEmpty(response.errorType)) "Ping successful"
               else "Ping failed: " ++ (response.description default "")
    }
  ]

/**
 * Build the overall ping response by aggregating endpoint results.
 * @param endpointResponses Array<{ name, status, message }>
 */
fun buildPingResponse(endpointResponses) =
  do {
    var statuses = (endpointResponses default []) map ((item) -> item.status)
    var anyDown  = (statuses default []) contains "DOWN"
    ---
    {
      name:     Mule::p("projectName"),
      status:   if (anyDown) "DOWN" else "UP",
      message:  if (anyDown) "One or more endpoints are DOWN"
                else "All endpoints are UP",
      endpoint: endpointResponses default []
    }
  }

// -----------------------------------------------------------------------------
// SOQL/Query helpers
// -----------------------------------------------------------------------------

/**
 * Generate a comma-separated list of named placeholders for an IN clause.
 * Ex: ids ->  ':idArg0', ':idArg1', ...
 * Caller is responsible for providing a params map with matching names.
 */
fun generateIdInClause(ids) =
  ((ids default [])
    distinctBy ($)
    map ((item, index) -> ("':idArg" ++ index ++ "'")))
    joinBy ", "

// -----------------------------------------------------------------------------
// Field utilities
// -----------------------------------------------------------------------------

/**
 * Given an object, return an array of field names whose values are empty.
 * Useful to populate Salesforce 'fieldsToNull' or similar patterns.
 */
fun buildFieldsToNull(data) =
  (
    (data pluck ((value, key) -> if (isEmpty(value)) key else null)) default []
  )
  filter ((item) -> !isEmpty(item))