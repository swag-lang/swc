// ============================================================================
// Parser Struct Ok
// ============================================================================

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
struct(A, B : s32 = 0, C = 5) A { }
