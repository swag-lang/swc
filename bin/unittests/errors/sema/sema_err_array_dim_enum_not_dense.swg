#global private

enum StartsAtOneArrayIndex
{
    First = 1
    Second
}

var startsAtOneValues: [StartsAtOneArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum NegativeArrayIndex
{
    BeforeFirst = -1
    First       = 0
}

var negativeValues: [NegativeArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum AboveCountArrayIndex
{
    First = 0
    Third = 2
}

var aboveCountValues: [AboveCountArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum DuplicateArrayIndex
{
    First     = 0
    AlsoFirst = 0
}

var duplicateValues: [DuplicateArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum ImplicitAfterGapArrayIndex
{
    First  = 0
    Third  = 2
    Fourth
}

var implicitAfterGapValues: [ImplicitAfterGapArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum HugeArrayIndex: u64
{
    First = 0
    Huge  = 18446744073709551615
}

var hugeValues: [HugeArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

enum StringArrayIndex: string
{
    First  = "first"
    Second = "second"
}

var stringValues: [StringArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

#[Swag.EnumFlags]
enum FlagArrayIndex: u8
{
    First
    Second
    Third
}

var flagValues: [FlagArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}
