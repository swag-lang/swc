#global private

#[Swag.ExportType(.Methods)]
struct(T) DeferredMethodProbe
{
    value: T
}

func reflectedMethod(type: typeinfo)->const *void?
{
    let info = cast #assume(const *Swag.TypeInfoStruct) type
    return info.methods![0].value
}

impl DeferredMethodProbe
{
    mtd get()->T
    {
        // Reflection must not wait on the generic body that is evaluating this #run.
        const pointer = #run reflectedMethod(#type DeferredMethodProbe's32)
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
    let pointer = reflectedMethod(#type DeferredMethodProbe's32)
    if pointer == null do
        return false
    let method = cast(func(const *DeferredMethodProbe's32)->s32) pointer
    return method(&probe) == 42
}

#test
{
    const result = #run callDeferredMethod()
    #assert(result)
}
