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

public struct DepIgnoredContainer {}

public impl DepIgnoredContainer
{
    const DEP_IMPL_VALUE = 47

    mtd run()
    {
        const DEP_LOCAL_VALUE = 53
    }
}
