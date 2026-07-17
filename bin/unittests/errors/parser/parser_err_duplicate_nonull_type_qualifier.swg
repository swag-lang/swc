#global private

// A type qualifier can appear at most once.
enum NonNullDuplicateQualifier: #nonull #nonull *s32 { Z } // swc-expected-error {{parser_err_duplicate_type_qualifier}}
