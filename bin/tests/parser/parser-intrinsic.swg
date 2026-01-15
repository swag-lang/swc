var a = @strlen()           // swc-expected-error {{parser_err_too_few_arguments}}
var b = @strlen(a, b + 4)   // swc-expected-error {{parser_err_too_many_arguments}}
