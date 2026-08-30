// 

#[Swag.Mixin]
func mixinInjectVoid(stmt: #code)
{
    #inject(stmt)
}

private func semaTest001()
{
    var value = 0
    mixinInjectVoid(#code
    {
        value += 1
    })

    Swag.assert(value == 1)
}

#[Swag.Mixin]
func mixinInjectValue(value: s32, stmt: #code)
{
    #inject(stmt)
    #inject(stmt)
}

private func semaTest002()
{
    var total = 0
    mixinInjectValue(4, #code
    {
        total += value
    })

    mixinInjectValue(2)
    {
        total += value
    }

    Swag.assert(total == 12)
}
