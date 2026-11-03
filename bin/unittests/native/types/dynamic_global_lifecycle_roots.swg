#global private

#[Swag.DynCast]
struct GlobalLifecycleRoot
{
    value: s32 = 73
}

var globalLifecycleRoot: GlobalLifecycleRoot

#test
{
    Swag.require(globalLifecycleRoot.value == 73)
}
