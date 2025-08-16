PARKING_PROFILE_SCHEMA = JSONSchemer.schema(
  {
    "$schema"=>"https://json-schema.org/draft/2020-12/schema",
    "type"=>"object",
    "required"=> %w[title types],
    "properties"=>{
      "title"=>{ "type"=>"string" },
      "summary_markdown"=>{ "type"=>"string" },
      "types"=>{
        "type"=>"array",
        "items"=> {
          "type"=>"object",
          "required"=> %w[code label],
          "properties"=> {
            "code"=>{ "type"=>"string" },
            "label"=>{ "type"=>"string" },
            "status"=>{ "enum"=> %w[open free paid reservations_required closed] },
            "links"=>{ "type"=>"array", "items"=>{ "type"=>"object", "required"=> %w[label url],
                                                "properties"=>{ "label"=>{ "type"=>"string" }, "url"=>{ "type"=>"string", "format"=>"uri" } } } }
          }
        }
      },
      "faqs"=>{ "type"=>"array", "items"=>{ "type"=>"object", "required"=> %w[q a],
                                         "properties"=>{ "q"=>{ "type"=>"string" }, "a"=>{ "type"=>"string" } } } }
    },
    "additionalProperties"=>true
  }
)
