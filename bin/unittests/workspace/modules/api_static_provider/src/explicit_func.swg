const PRIVATE_FACTOR = 3

#[Swag.Discardable, Swag.NoInline, Swag.Safety(.All, false), Swag.Sanity(.All, false), Swag.Optimize(false), Swag.Warning("all", .Disable), Swag.NoDoc]
public func depTriple(value: s32)->s32
{
    return value * PRIVATE_FACTOR
}
