#global private

// A method of a 'private impl' belongs to its type, so another file calls it neither directly
// nor through a 'with' subject. An overload set keeps the overloads this file can reach.
#test
{
    var s: AccessSafe
    Swag.assert(s.pick(1) == 5)
}

#test
{
    var s: AccessSafe
    discard s.secret()     // swc-expected-error {{sema_err_method_private}}
}

#test
{
    with var s: AccessSafe
    {
        discard .secret()     // swc-expected-error {{sema_err_method_private}}
    }
}
