#global private

// A 'readonly' field reads wherever its level allows and writes only from its own type.
#test
{
    var c: AccessCounter
    c.bump()
    @assert(c.count == 1)
}

#test
{
    var c: AccessInternalCounter
    c.bump()
    @assert(c.count == 1)
}

#test
{
    var c: AccessInternalCounter
    c.count = 5     // swc-expected-error {{sema_err_field_readonly}}
}

#test
{
    var c: AccessCounter
    c.count = 5     // swc-expected-error {{sema_err_field_readonly}}
}

#test
{
    var c: AccessCounter
    c.count += 1     // swc-expected-error {{sema_err_field_readonly}}
}

// The address of a read-only field is a pointer to const, so a mutable pointer cannot bind it.
func write(p: *s32) { dref p = 1 }

#test
{
    var c: AccessCounter
    write(&c.count)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    let c = AccessCounter{3}     // swc-expected-error {{sema_err_struct_cast_field_access}}
}
