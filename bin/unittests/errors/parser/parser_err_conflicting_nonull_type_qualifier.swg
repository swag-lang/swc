#global private

// A type cannot be explicitly nullable and explicitly non-null at the same time.
enum NullThenNonNullQualifier: #null #nonull *s32 { Z } // swc-expected-error {{parser_err_conflicting_type_qualifier}}
enum NonNullThenNullQualifier: #nonull #null *s32 { Z } // swc-expected-error {{parser_err_conflicting_type_qualifier}}
