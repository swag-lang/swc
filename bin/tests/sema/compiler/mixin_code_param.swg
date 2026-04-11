// 

#[Swag.Mixin]
func mixinInjectVoid(stmt: #code void)
{
    #inject(stmt)
}

#test
{
    var value = 0
    mixinInjectVoid(#code
    {
        value += 1
    })

    @assert(value == 1)
}

#[Swag.Mixin]
func mixinInjectValue(value: s32, stmt: #code void)
{
    #inject(stmt)
    #inject(stmt)
}

#test
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

    @assert(total == 12)
}

