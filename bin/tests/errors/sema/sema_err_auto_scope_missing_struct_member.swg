#global fileprivate

struct Vec2
{
    x: f32
    y: f32
}

impl Vec2
{
    mtd toto()
    {
        if .z > 0.0 {} // swc-expected-error {{sema_err_auto_scope_missing_struct_member}}
    }
}
