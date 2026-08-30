#global private

// A member belongs to its type, so 'private' grants the file that declares the aggregate and
// every 'impl' of that type. Another file reaches neither, even to read.
#test
{
    var s: AccessSafe
    Swag.assert(s.read() == 5)
}

#test
{
    var s: AccessSafe
    Swag.assert(s.key == 5)     // swc-expected-error {{sema_err_field_private}}
}

#test
{
    var s: AccessSafe
    s.key = 7     // swc-expected-error {{sema_err_field_private}}
}

// Embedding the owner grants nothing: the embedder is not the declaring type.
impl AccessHost
{
    mtd peek()->s32 => .key     // swc-expected-error {{sema_err_field_private}}
}

// Naming a field in a literal writes it, so the write rule applies to literals too.
#test
{
    let s = AccessSafe{key: 1}     // swc-expected-error {{sema_err_struct_cast_field_access}}
}
