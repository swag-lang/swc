SWC_DIAG_DEF(parser_note_reserved_identifier, Note, "a {tok-fam} cannot be used as an identifier")
SWC_DIAG_DEF(parser_note_other_def, Note, "this is the other definition")
SWC_DIAG_DEF(parser_note_opening, Note, "opening delimiter")
SWC_DIAG_DEF(parser_note_gen_param_type, Note, "this implies a generic type and not a typed value")

SWC_DIAG_DEF(parser_help_empty_array_dim, Help, "expected one of '[*]' (pointer), '[..]' (slice), '[?]' (inferred array), or a numeric dimension")
SWC_DIAG_DEF(parser_help_gen_param_type, Help, "use 'const' instead of 'var' to declare a generic value")

SWC_DIAG_DEF(sema_note_signed_unsigned, Note, "value is negative, but the target type is unsigned")
SWC_DIAG_DEF(sema_note_unsigned_signed, Note, "value is greater than the maximum value of the signed target type")
SWC_DIAG_DEF(sema_note_cast_explicit, Note, "you can cast the value explicitly")
SWC_DIAG_DEF(sema_note_other_definition, Note, "this is the other definition")
