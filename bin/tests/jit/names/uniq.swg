#global fileprivate

#[Swag.Mixin]
func mixinUniq(value: s32)
{
    var #uniq0 = value + 1
    total += #uniq0
    {
        var #uniq0 = value + 10
        total += #uniq0
    }
    total += #uniq0
}

func computeUniq(value: s32)->s32
{
    var total = 100
    var marker = 7
    mixinUniq(value)
    mixinUniq(value + 2)
    @assert(marker == 7)
    return total
}

#run
{
    @assert(computeUniq(3) == 148)
}

#test
{
    var #uniq0 = 1
    var #uniq0 = 2 // swc-expected-error {{sema_err_already_defined}}
}
