enum A
{
    #if A do
        A = 0
    #else {
        A = 1
    }
}

enum A
{
    #assert(A)
    B,
    C,
}

enum A
{
    #if A == 0 do
        A = 0
    #else {
        A = 1
    }
}

enum A
{
    B = 0
    C = 1
}

enum A { B, C }
enum A { B, C, }

enum A
{
    B,
    C,
}

enum A
{
    B
    C
}

enum
A
{
    B
    C
}

enum A
{
    B = 0,
    C = 1,
}

enum A { B = 1's8, }
enum A { B = 1's16, }
enum A { B = 1's32, }
enum A { B = 1's64, }
enum A { B = 1'u8, }
enum A { B = 1'u16, }
enum A { B = 1'u32, }
enum A { B = 1'u64, }
enum A { B = 1'f32, }
enum A { B = 1'f64, }
enum A { B = 1'T, }
enum A { B = 1'TTT_TTT, }
enum A { B = 1'bool, }
enum A { B = 1'rune, }

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

enum A {}

enum A } // swc-expected-error {{parser_err_expected_token_before}}

