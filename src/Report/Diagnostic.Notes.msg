SWC_DIAG_DEF(parser_note_reserved_identifier, Note, "A {tok-fam} cannot be used as an identifier")
SWC_DIAG_DEF(parser_note_other_def, Note, "This is the other definition")
SWC_DIAG_DEF(parser_note_opening, Note, "Opening delimiter")
SWC_DIAG_DEF(parser_note_gen_param_type, Note, "This expression implies a generic type rather than a typed value")

SWC_DIAG_DEF(parser_help_empty_array_dim, Help, "Expected one of '[*]' (pointer), '[..]' (slice), '[?]' (inferred array), or a numeric dimension")
SWC_DIAG_DEF(parser_help_gen_param_type, Help, "Use 'const' instead of 'var' to declare a generic value")

SWC_DIAG_DEF(sema_note_signed_unsigned, Note, "The value is negative, but the target type is unsigned")
SWC_DIAG_DEF(sema_note_unsigned_signed, Note, "The value exceeds the maximum value of the signed target type")
SWC_DIAG_DEF(sema_note_cast_explicit, Note, "You could cast the value explicitly")
SWC_DIAG_DEF(sema_note_other_definition, Note, "The other definition of {tok} is here")
SWC_DIAG_DEF(sema_note_could_be, Note, "Could be")
SWC_DIAG_DEF(sema_note_cyclic_dependency_link, Note, "Waiting ...")
SWC_DIAG_DEF(sema_note_strict_alias, Note, "The attribute '#[Swag.Strict]' can only be applied to a type alias")

SWC_DIAG_DEF(sema_help_nameof_instruction, Help, "Use '#stringof' to convert a constant expression to a string")
