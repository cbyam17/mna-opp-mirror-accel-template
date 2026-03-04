%dw 2.0

fun buildPingEndpointResponse(name, response) =
[{
	name: name,
	status: if ( isEmpty(response.errorType) ) "UP"
		else "DOWN",
	message: if ( isEmpty(response.errorType) ) "Ping successful"
		else "Ping failed: " ++ response.description
}]

fun buildPingResponse(endpointResponses) =
	{
	name: Mule::p("projectName"),
	status: if ( (endpointResponses.status default []) contains("DOWN") ) "DOWN"
		else "UP",
	message: if ( (endpointResponses.status default []) contains("DOWN") ) "One or more endpoints are DOWN"
		else "All endpoints are UP",
	endpoint: endpointResponses default []
}

// required?
fun appendZIfNeeded(dateTimeStr) =
	if ( !isEmpty(dateTimeStr) )
		if ( endsWith(dateTimeStr, "Z") ) dateTimeStr
		else dateTimeStr ++ "Z"
	else dateTimeStr
	
fun generateIdInClause(ids) =
	ids default [] distinctBy ((item) -> item) default []
		map ((item, index) -> ("':idArg") ++ index ++ "'") joinBy ", "

fun buildFieldsToNull(data) =
	data pluck ((value, key, index) -> (if ( isEmpty(value) ) key else null)) default []
		filter ((item) -> !isEmpty(item)) default []
