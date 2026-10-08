#global private

struct Single1 {x: s32}
struct Single2 {x: f32}

#test
{
    const SINGLE1: Single1 = {1}
    const SINGLE2: Single2 = SINGLE1     // swc-expected-error {{sema_err_struct_cast_field_type}}
}

// A value of a struct-literal type has no field expressions to convert: at run time it is
// copied as it is, so its field types must already match.
func convert(source: s32)
{
    let value = {x: source}
    let single: Single2 = value     // swc-expected-error {{sema_err_struct_cast_field_type}}
    discard single
}
