// ============================================================================
// PbEntry Module DataWeave
// ============================================================================

%dw 2.0

// ============================================================================
// Externalized SRC <-> TGT PricebookEntryId mapping via JSON-in-properties
//  - Reads JSON map from Mule property: p("pbe.map.json") (secure or regular)
//  - Supports one or both directions:
//      SRC_to_TGT: { "<srcId>": "<tgtId>", ... }
//      TGT_to_SRC: { "<tgtId>": "<srcId>", ... } // optional; auto-derived if missing
//  - Public API:
//      parsePbeMap()                -> { SRC_to_TGT: Object, TGT_to_SRC: Object }
//      mapPbEntryId(id, "_TGT|_SRC")-> String | Null
//      mapToTgt(id)                 -> String | Null
//      mapToSrc(id)                 -> String | Null
// ============================================================================

/**
 * Safely parse JSON from the property; returns empty object if missing or malformed.
 */
fun readPbePropertyAsJson() =
  do {
    var raw = Mule::p("pbe.map.json") as String default ""  // works for secure:: and regular
    ---
    if (raw == null or raw == "") {} else (read(raw, "application/json") as Object) default {}
  }

/** Construct reverse map (value->key) from a forward map (key->value). */
fun reverseMap(o) =
  (
    (o default {})
      pluck ((v, k) -> { (v as String): (k as String) })
      reduce ((acc = {}, item) -> acc ++ item)
  ) default {}

/** Normalize map structure and ensure both directions are present. */
fun normalizeMaps(m) =
  do {
    var forward = (m.SRC_to_TGT default {})
    var reverse = (m.TGT_to_SRC default reverseMap(forward))
    ---
    {
      SRC_to_TGT: forward,
      TGT_to_SRC: reverse
    }
  }

/** Load and normalize the mapping once per call (side-effect free). */
fun parsePbeMap() = normalizeMaps(readPbePropertyAsJson())

/**
 * Bidirectional map for PricebookEntryId.
 * @param pbEntryId   String
 * @param destination "_TGT" (SRC->TGT) or "_SRC" (TGT->SRC)
 */
fun mapPbEntryId(pbEntryId, destination) =
  do {
    var id   = pbEntryId as String default null
    var maps = parsePbeMap()
    ---
    if (id == null) null
    else if (destination == "_TGT") (maps.SRC_to_TGT[id] default null)
    else if (destination == "_SRC") (maps.TGT_to_SRC[id] default null)
    else null
  }

/** Convenience wrappers. */
fun mapToTgt(srcPbEntryId) = mapPbEntryId(srcPbEntryId, "_TGT")
fun mapToSrc(tgtPbEntryId) = mapPbEntryId(tgtPbEntryId, "_SRC")