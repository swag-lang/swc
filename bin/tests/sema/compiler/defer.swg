#global fileprivate

var G: s32 = 0

#[Swag.Mixin]
func mixinDeferredGlobal()
{
    defer G = 1
}

#[Swag.Macro]
func macroInject(stmt: #code void)
{
    #inject(stmt)
}

#test
{
    mixinDeferredGlobal()
}

#test
{
    var value = 0
    macroInject(#code {
        defer value = 1
    })
}

#test
{
    var value = 0
    for 1
    {
        macroInject(#code {
            defer value += 1
        })
    }
}

// Legacy compiler migrations that currently fail or hit compiler assertions:
// compiler2195
// compiler2240
// compiler2636
// compiler2805
// compiler3719
// compiler3775
// compiler5208
