// A failed check must return to the calling test across the shared-library boundary.
#[Swag.NoInline]
public func ctxSharedCheckedResult()->s32
{
    Swag.check(false, "expected check failure from the shared provider")
    return 42
}
