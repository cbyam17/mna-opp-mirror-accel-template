// ============================================================================
// Common Utilities Module DataWeave
// ============================================================================

%dw 2.0

/**
 * Build a single endpoint ping response.
 *
 * @param name     String
 * @param response Object (expects errorType?, description?)
 * @return Array<Object> (one element, simplifies aggregation)
 */
fun buildPingEndpointResponse(name, response) =
  [
    {
      name:    name,
      status:  if (isEmpty(response.errorType)) "UP" else "DOWN",
      message: if (isEmpty(response.errorType))
                 "Ping successful"
               else
                 "Ping failed: " ++ (response.description default "")
    }
  ]

/**
 * Build the overall ping response by aggregating endpoint results.
 *
 * @param endpointResponses Array<{ name, status, message }>
 * @return Object
 */
fun buildPingResponse(endpointResponses) =
  do {
    var statuses = (endpointResponses default []) map ((item) -> item.status)
    var anyDown  = (statuses default []) contains "DOWN"
    ---
    {
      name:    Mule::p("projectName"),
      status:  if (anyDown) "DOWN" else "UP",
      message: if (anyDown) "One or more endpoints are DOWN" else "All endpoints are UP",
      endpoint: endpointResponses default []
    }
  }

/**
 * Generate a comma-separated list of named placeholders for an IN clause.
 * Example: ids -> ":idArg0", ":idArg1", ...
 *
 * NOTE: This implementation adds single quotes around placeholders.
 *       If your target driver expects raw bind placeholders (without quotes),
 *       remove the quotes below.
 */
fun generateIdInClause(ids) =
  ((ids default [])
    distinctBy ($)
    map ((item, index) -> ("':idArg" ++ index ++ "'")))
  joinBy ", "

/**
 * Given an object, return an array of field names whose values are empty.
 * Useful to populate Salesforce 'fieldsToNull' or similar patterns.
 *
 * @param data Object
 * @return Array<String>
 */
fun buildFieldsToNull(data) =
  (
    (data pluck ((value, key) -> if (isEmpty(value)) key else null)) default []
  )
  filter ((item) -> !isEmpty(item))

/**
 * Normalize an input to an Array:
 * - Array -> same array
 * - null  -> []
 * - other -> [value]
 */
fun toArray(v) =
  if (v is Array) v
  else if (v == null) []
  else [v]

/** Safe-filter-then-first pattern. */
fun firstOrNull(arr) = ((arr default []) as Array)[0] default null

/**
 * Null-safe string truncate.
 *
 * @param value  Any (converted to String if not null)
 * @param maxLen Number
 * @return String | Null
 */
fun truncate(value, maxLen) =
  if (value == null)
    null
  else
    (value as String)[0 to (maxLen - 1)]