#global public
namespace DepTools
{
    const DEP_NAMESPACE_C = 41
}

namespace DepTools.Deep
{
    const DEP_NAMESPACE_DEEP = 43
}

// Whether a return value can be dropped is a fact about the call site, so it has to survive the
// module boundary. Both functions carry the attribute from an enclosing block, which is where
// the exported declaration has nothing of its own to copy.
#[Swag.Discardable]
{
    func depDiscardableCount()->u32 => 61

    #[Swag.Inline]
    func depDiscardableInlineCount()->u32 => 67
}

// An exported body is compiled again by the importer, and its unmarked fallible calls only
// read as 'try' there if 'Swag.Propagate' travels with it. Both bodies take the attribute
// from an enclosing block, so the exported declarations have nothing of their own to copy.
struct DepPropagateError
{
    using base: Swag.BaseError
}

func depPropagateStep(ok: bool)->s32 fail
{
    if not ok do
        fail DepPropagateError{base: Swag.BaseError{"step"}}
    return 20
}

#[Swag.Propagate]
{
    func(T) depPropagateGeneric(value: T, ok: bool)->T fail
    {
        discard depPropagateStep(ok)
        return value
    }

    #[Swag.Inline]
    func depPropagateInline(ok: bool)->s32 fail => depPropagateStep(ok) + 1
}

public struct DepIgnoredContainer {}

public impl DepIgnoredContainer
{
    const DEP_IMPL_VALUE = 47

    mtd run()
    {
        const DEP_LOCAL_VALUE = 53
    }
}
