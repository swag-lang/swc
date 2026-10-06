#global private

#[Swag.DynCast]
struct GlobalLifecycleRoot
{
    value: s32 = 73
}

var globalLifecycleRoot: GlobalLifecycleRoot

#test
{
    Swag.assert(globalLifecycleRoot.value == 73)
}
