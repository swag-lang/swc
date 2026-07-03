#global private

// A function-typed struct field (`func(...)`) holds a code address that is not resolved until
// link time, so it cannot be const-folded from a constant container's bytes. Accessing such a
// field through a compile-time-constant container (here a `typeinfo` cast) must fall back to a
// runtime member read instead of hard-erroring "struct field type 'func(*void)' cannot be
// evaluated at compile time". TypeInfoStruct.opDrop is exactly such a field.

struct WithDrop
{
    value: s32
}

impl WithDrop
{
    mtd opDrop() {}
}

struct PlainPod
{
    value: s32
}

#test
{
    // Const container (the typeinfo cast is a compile-time constant pointer); the member is a
    // `func(*void)` field. This used to fail to compile; it must now read opDrop at runtime.
    let dropPtr  = (cast(const *Swag.TypeInfoStruct) #typeof(WithDrop)).opDrop
    let plainPtr = (cast(const *Swag.TypeInfoStruct) #typeof(PlainPod)).opDrop

    @assert(dropPtr != null)
    @assert(plainPtr == null)
}
