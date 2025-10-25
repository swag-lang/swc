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
    const auto& info = AST_NODE_ID_INFOS[static_cast<int>(n.id)];

    if (info.flags.has(AstNodeIdFlagsEnum::ArityMany))
    {
        return {.ptr = nodeRefs_.ptr(n.slice.index), .n = n.slice.count};
    }

    return {};
}

SWC_END_NAMESPACE();
