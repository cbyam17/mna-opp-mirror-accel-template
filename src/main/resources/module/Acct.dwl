%dw 2.0
import generateIdInClause from module::CommonUtil

fun buildQueryAcctsById_TGT(ids) =
	{
		// adjust _TGT SOQL query per requirements
		query:	"SELECT Id, OwnerId FROM Account WHERE Id IN (" ++ generateIdInClause(ids) ++ ")",
		queryParams: ids default [] distinctBy ((item) -> item) default []
			map ((item,index) -> {
				(("idArg") ++ index): item
		}) reduce ((item, accumulator = {}) -> item ++ accumulator)
	}