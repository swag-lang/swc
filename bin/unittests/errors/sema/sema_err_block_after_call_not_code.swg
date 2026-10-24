#global private

func plain(value: s32)->s32 => value

#[Swag.Macro]
func repeat(count: s32, stmt: #code)
{
    for count do
        #inject(stmt)
}

// A block after a call is the trailing code of that call, so the call must take code.
#test
{
    var total = 0
    repeat(2)
    {
        total += 1
    }

    Swag.assert(total == 2)
}

#test
{
    discard plain(1)
    {     // swc-expected-error {{sema_err_block_after_call_not_code}}
        discard plain(2)
    }
}
