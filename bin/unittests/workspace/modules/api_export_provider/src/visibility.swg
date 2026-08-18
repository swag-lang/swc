#global public

// Proves the narrowest useful placement of file, impl, field, and readonly access modifiers.
struct DepVisibility
{
    public
    {
        writable: s32
        readonly observed: s32
    }

    moduleState: s32
    readonly moduleObserved: s32
    private secret: s32
}

// The file default publishes the type's supported operations without repeating 'public'.
impl DepVisibility
{
    func create(writable, observed, moduleState, secret: s32)->DepVisibility
    {
        return {writable: writable, observed: observed, moduleState: moduleState, moduleObserved: moduleState + 1, secret: secret}
    }

    mtd total()->s32 => .writable + .observed + .moduleState + .moduleObserved + .secret
}

// A different method family states its level once on its impl.
internal impl DepVisibility
{
    mtd moduleValue()->s32 => .moduleState + .moduleObserved
}

private impl DepVisibility
{
    mtd secretValue()->s32 => .secret
}
