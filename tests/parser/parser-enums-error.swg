// ============================================================================
// Parser Enums Error
// ============================================================================

enum A
{
    #if A do
        A = 0
    #else // swc-expected-error {{parser_err_expected_do_block}}
        A = 1
}

enum  { } // swc-expected-error {{parser_err_expected_token_fam_before}}
enum enum {  Z } // swc-expected-error {{parser_err_expected_token_fam_before}}
enum #ast { Z  } // swc-expected-error {{parser_err_expected_token_fam_before}}
enum A B { C } // swc-expected-error {{parser_err_expected_token_before}}
enum A { B,, C } // swc-expected-error {{parser_err_unexpected_token}}

enum A { B = 1' } // swc-expected-error {{parser_err_empty_literal_suffix}}
enum A { B = 1', } // swc-expected-error {{parser_err_empty_literal_suffix}}

enum A { B = 1'any } // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum A { B = 1'string } // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum A { B = 1'cstring } // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum A { B = 1'cvarargs } // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum A { B = 1'typeinfo } // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum A { B = 1'void } // swc-expected-error {{parser_err_invalid_literal_suffix}}

enum A {} // swc-expected-error {{parser_err_empty_enum}}

enum A } // swc-expected-error {{parser_err_expected_token_before}}
enum A toto } // swc-expected-error {{parser_err_expected_token_before}} {{parser_err_unexpected_token}}

enum A { B C } // swc-expected-error {{parser_err_missing_enum_sep}}
