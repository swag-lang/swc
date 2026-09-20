const PRIVATE_VALUE    = 99
public const DEP_VALUE = 7

public func depFutureExport()->s32
{
    return DEP_VALUE
}

public func(T) depGenericIdentity(value: T)->T => value

// Provides an imported generic `create` overload family for workspace regression coverage.
public struct DepOverloadWnd {}

public impl DepOverloadWnd
{
    // Resolves the imported generic overload family without a position.
    #[Swag.Inline]
    func(T) create(parent: *DepOverloadWnd? = null, id: string? = null, hook: func||()? = null)->*T? => create'T(parent, "", {}, id, hook)

    // Resolves the imported generic overload family at `position`.
    #[Swag.Inline]
    func(T) create(parent: *DepOverloadWnd?, position: DepOverloadWnd, id: string? = null, hook: func||()? = null)->*T? => create'T(parent, "", position, id, hook)

    // Returns no window from the fully specified imported generic overload.
    func(T) create(parent: *DepOverloadWnd?, name: string?, position: DepOverloadWnd, id: string? = null, hook: func||()? = null)->*T? => null
}
