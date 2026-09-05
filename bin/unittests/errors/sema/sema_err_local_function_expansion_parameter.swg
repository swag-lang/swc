#global private

// A local function of a macro is a function of its own: the macro's parameter is bound to an
// expression of the caller's frame, which that function cannot reach. The value goes in as an
// argument of the local function instead, as 'Jobs.parallelFor' does.
#[Swag.Macro]
func visitOnce(count: u32, stmt: #code(index: u32))
{
    func visit()
    {
        var index = 0'u32
        for count     // swc-expected-error {{sema_err_local_function_expansion_parameter}}
        {
            #inject(stmt, index = index)
            index += 1
        }
    }

    visit()
}

func bad(count: u32)->u32
{
    visitOnce(count) #code(index)     // swc-expected-note {{sema_note_expansion_invoked_here}}
    {
        Swag.assert(index < 1)
    }
    return 0
}

const TriggerBad = #run bad(1)
