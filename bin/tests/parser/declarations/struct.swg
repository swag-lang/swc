struct A {}
struct A
{
}

struct FormLine
{
    #[Serialization.NoSerialize]
    {
    }
}

// Generic parameters
struct(T) A { }
struct(A, B) A { }
struct(A, B, C) A { }
struct(A, B : s32, C) A { }
struct(A, B : s32 = 0, C) A { }
struct(A, B : s32 = 0, C = bool) A { }
struct(var A, const B) A { }
struct(var A = s32, const B = 0) A { }
struct(var A = s32, const B: s32 = 0) A { }
struct(var A = [..] s32, const B: s32 = 0) A { }

struct(var T : s32) A { } // swc-expected-error {{parser_err_gen_param_type}}
struct(T = 0) A { } // swc-expected-error {{parser_err_invalid_type}}

