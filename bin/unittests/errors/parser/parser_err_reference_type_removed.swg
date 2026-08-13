#global private

// Reference types were removed from the language; '*T' is the only indirection.
func f(x: &s32) {}                  // swc-expected-error {{parser_err_reference_type_removed}}
enum A : &A { Z }                   // swc-expected-error {{parser_err_reference_type_removed}}

#test
{
    var v: [..] &s32                // swc-expected-error {{parser_err_reference_type_removed}}
}
