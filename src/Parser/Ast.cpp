#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

Ast::Ast()
{
    // Push an invalid node first so that valid references start at 1.
    makeNode(AstNodeId::Invalid, INVALID_REF);
}

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
