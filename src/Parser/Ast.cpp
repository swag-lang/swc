#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstChildrenView Ast::children(const AstNode& n) const
{
    switch (n.payloadKind)
    {
        case AstPayloadKind::SliceKids:
        {
            const auto& sl = sliceStore_.at(n.payloadRef);
            return {.ptr = nodeRefs_.ptr(sl.first), .n = sl.count};
        }
        default:
            return {};
    }
}

SWC_END_NAMESPACE();
