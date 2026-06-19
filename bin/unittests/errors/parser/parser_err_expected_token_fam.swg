#global fileprivate

// Expected a token family (e.g. an identifier), found the wrong family or a reserved word.
impl A.B. { }                     // swc-expected-error {{parser_err_expected_token_fam}}
using namespace Foo               // swc-expected-error {{parser_err_expected_token_fam}}
using 42                          // swc-expected-error {{parser_err_expected_token_fam}}
