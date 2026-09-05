#global private

#print()     // swc-expected-error {{parser_err_too_few_arguments}}

const Empty = #stringof()     // swc-expected-error {{parser_err_too_few_arguments}}

#ast()     // swc-expected-error {{parser_err_too_few_arguments}}
