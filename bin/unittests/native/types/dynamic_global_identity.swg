#global private

#[Swag.DynCast]
struct GlobalBase { value: s32 = 12 }

struct GlobalOwner
{
    prefix: u64 = 31
    using base: GlobalBase
}

var owners: [2] GlobalOwner
var task: Swag.Task
var completed: Swag.AtomicFlag

#test
{
    for &owner in owners
    {
        let base = &owner.base
        Swag.assert(cast #try (*GlobalOwner) base == owner)
        Swag.assert(cast #assume (*GlobalOwner) base == owner)
        Swag.assert(base.value == 12)
        Swag.assert(owner.prefix == 31)
    }
}

#test
{
    task.submit(func() { discard completed.raise() })
    task.wait()
    Swag.assert(completed.isRaised())
}
