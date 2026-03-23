// ============================================================================
// PbEntry Module DataWeave
// ============================================================================

%dw 2.0

// Parse JSON from the property; returns empty object if missing or malformed.
fun readPbePropertyAsJson() =
  do {
    var raw = Mule::p("pbe.map.json") as String default ""
    ---
    if (raw == null or raw == "")
      {}
    else 
      (read(raw, "application/json") as Object) default {}
  }

// Construct reverse map (value->key) from a forward map (key->value)
fun reverseMap(o) =
  (
    (o default {})
      pluck ((v, k) -> { (v as String): (k as String) })
        reduce ((acc = {}, item) -> acc ++ item)
  ) default {}

// Normalize map structure and ensure both directions are present (SRC->TGT and TGT->SRC)
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

// Load and normalize the mapping once per call
fun parsePbeMap() = normalizeMaps(readPbePropertyAsJson())

// Bidirectional map for PricebookEntryId
fun mapPbEntryId(pbEntryId, destination) =
  do {
    var id = pbEntryId as String default null
    var maps = parsePbeMap()
    ---
    if (id == null)
      null
    else if (destination == "_TGT")
      (maps.SRC_to_TGT[id] default null)
    else if (destination == "_SRC")
      (maps.TGT_to_SRC[id] default null)
    else
      null
  }

// Convenience wrappers
fun mapToTgt(srcPbEntryId) = mapPbEntryId(srcPbEntryId, "_TGT")
fun mapToSrc(tgtPbEntryId) = mapPbEntryId(tgtPbEntryId, "_SRC")