#global fileprivate

struct Single1 {x: s32}
struct Single2 {x: f32}

#test
{
    const SINGLE1: Single1 = {1}
    const SINGLE2: Single2 = SINGLE1 // swc-expected-error {{sema_err_struct_cast_field_type}}
}
