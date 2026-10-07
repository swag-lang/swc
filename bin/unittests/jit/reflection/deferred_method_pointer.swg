#global private

#[Swag.ExportType(.Methods)]
struct(T) DeferredMethodProbe
{
    value: T
}

var MethodReads: s32
#[Swag.NoInline]
func reflectedMethod()->const *void?
{
    MethodReads += 1
    let info = cast(const *Swag.TypeInfoStruct, #type DeferredMethodProbe's32)
    return info.methods![0].value
}

impl DeferredMethodProbe
{
    #[Swag.NoInline]
    mtd get()->T
    {
        // Reflection must not wait on the generic body that is evaluating this #run.
        const pointer = #run reflectedMethod()
        #assert(pointer == null)
        return .value
    }
}

func callDeferredMethod()->bool
{
    var probe = DeferredMethodProbe's32{value: 42}
    if probe.get() != 42 do
        return false

    // Reuse the already JIT-compiled reader after the method acquires an address.
    let pointer = reflectedMethod()
    if pointer == null do
        return false
    let method = cast(func(const *DeferredMethodProbe's32)->s32, pointer)
    return method(&probe) == 42
}

#test
{
    const result = #run callDeferredMethod()
    #assert(result)
}
