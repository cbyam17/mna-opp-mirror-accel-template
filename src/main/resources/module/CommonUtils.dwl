// ============================================================================
// Common Utilities Module DataWeave
// ============================================================================

%dw 2.0
fun buildHealthCheckEndpointResponse(name, response) =
  [
    {
      name: name,
      status:
        if (isEmpty(response.errorType))
          "UP"
        else
          "DOWN",
      message:
        if (isEmpty(response.errorType))
          "Ping successful"
        else
          "Ping failed: " ++ (response.description default "")
    }
  ]

fun buildHealthCheckResponse(endpointResponses) =
  do {
    var statuses =
      (endpointResponses default [])
        map ((item) -> item.status)
    var anyDown = (statuses default []) contains "DOWN"
    ---
    {
      name: Mule::p("projectName"),
      status: 
        if (anyDown)
          "DOWN"
        else
          "UP",
      message:
        if (anyDown)
          "One or more endpoints are DOWN"
        else
          "All endpoints are UP",
      endpoint: endpointResponses default []
    }
  }

fun generateIdInClause(ids) =
  ((ids default [])
    distinctBy ($)
      map ((item, index) -> ("':idArg" ++ index ++ "'")))
  joinBy ", "

fun toArray(v) =
  if (v is Array)
    v
  else if (v == null)
    []
  else
    [v]

fun firstOrNull(arr) =
  ((arr default []) as Array)[0] default null

fun truncate(value, maxLen) =
  if (value == null)
    null
  else if (sizeOf((value as String)) <= maxLen)
    (value as String)
  else
    (value as String)[0 to (maxLen - 1)]