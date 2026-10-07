#global private

#[Swag.ExportType(.Methods)]
struct(T) DeferredConstantProbe
{
    value: T
}

#[Swag.NoInline]
func reflectedMethod()->const *void?
{
    let info = cast(const *Swag.TypeInfoStruct, #type DeferredConstantProbe's32)
    return info.methods![0].value
}

#[Swag.NoInline]
func forwardedMethod()->const *void?
{
    return reflectedMethod()
}

impl DeferredConstantProbe
{
    mtd get()->T
    {
        // The reader reaches this unfinished method through its own constant
        // graph, with no pointer argument to expose the unpublished address.
        const pointer = #run forwardedMethod()
        #assert(pointer == null)
        return .value
    }
}

func callPublishedMethod()->bool
{
    var probe = DeferredConstantProbe's32{value: 73}
    if probe.get() != 73 do
        return false

    // Reusing either the target closure or the constant-call result must still
    // observe the address published after the earlier compile-time request.
    let first  = forwardedMethod()
    let second = forwardedMethod()
    if first == null or second != first do
        return false
    let method = cast(func(const *DeferredConstantProbe's32)->s32, first)
    return method(&probe) == 73
}

#test
{
    const result = #run callPublishedMethod()
    #assert(result)
}
