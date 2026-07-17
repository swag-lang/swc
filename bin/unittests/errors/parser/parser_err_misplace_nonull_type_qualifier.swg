#global private

// Canonical qualifier order is '#nonull const T'.
enum MisplacedNonNullQualifier: const #nonull *s32 { Z } // swc-expected-error {{parser_err_misplace_type_qualifier}}

func misplacedNonNullParameter(value: const #nonull *s32) {} // swc-expected-error {{parser_err_misplace_type_qualifier}}
