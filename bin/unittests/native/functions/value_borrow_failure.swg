#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct Owner
{
    values: [4]u64
    drops:  *u64
}

impl Owner
{
    mtd opDrop()
    {
        .values[0] = 0
        .drops[]   += 1
    }
}

#[Swag.NoInline]
func consume(value: Owner, rejected: bool)->u64 fail
{
    if rejected do
        fail 17's32
    return value.values[0]
}

#[Swag.NoInline]
func reject()->bool fail { fail 19's32 }

func forward(drops: *u64, rejected: bool)->u64 fail =>
    try consume(Owner{[23, 0, 0, 0], drops}, rejected)

#test
{
    var drops: u64
    Swag.assert((expect forward(&drops, false)) == 23)
    Swag.assert(drops == 1)
    var outcome: Swag.Error
    discard catch forward(&drops, true) as outcome
    Swag.assert(outcome.value() != null and drops == 2)
}

#test
{
    var drops:   u64
    var outcome: Swag.Error
    discard catch consume(Owner{[29, 0, 0, 0], &drops}, try reject()) as outcome
    Swag.assert(outcome.value() != null and drops == 1)
}

#test
{
    var drops: u64
    let value = expect consume(Owner{[31, 0, 0, 0], &drops}, catch reject() orelse false)
    Swag.assert(value == 31 and drops == 1)
}

#[Swag.NoInline]
func mutate(value: *Owner)->u64
{
    value.values[0] = 0
    return 0
}

#test
{
    var drops: u64
    var owner = Owner{[37, 0, 0, 0], &drops}
    let panic = Swag.catchPanic(func|&owner, &drops|() {
        discard expect consume(owner, (catch consume(Owner{[41, 0, 0, 0], &drops}, true) orelse mutate(&owner)) != 0)
    })
    Swag.assert(panic.raised and owner.values[0] == 37 and drops == 1)
}

#[Swag.Inline]
func failInline(value: Owner, destination: *Owner, drops: *u64) fail
{
    defer destination.values[0] = value.values[0] + 1
    discard try consume(Owner{[43, 0, 0, 0], drops}, true)
}

#test
{
    var drops: u64
    var owner = Owner{[47, 0, 0, 0], &drops}
    let panic = Swag.catchPanic(func|&owner, &drops|() {
        catch failInline(owner, &owner, &drops)
    })
    Swag.assert(panic.raised and owner.values[0] == 47 and drops == 1)
}

#test
{
    var drops: u64
    let value = expect consume(Owner{[53, 0, 0, 0], &drops}, (catch consume(Owner{[59, 0, 0, 0], &drops}, true) orelse 0) != 0)
    Swag.assert(value == 53 and drops == 2)
}
