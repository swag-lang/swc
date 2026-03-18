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

