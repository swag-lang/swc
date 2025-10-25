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
    const auto& info = nodeIdInfos(n.id);

    switch (info.arity)
    {
        case AstNodeIdArity::None:
            return {};
        case AstNodeIdArity::One:
            return {.ptr = &n.one.first, .count = 1};
        case AstNodeIdArity::Two:
            return {.ptr = &n.two.first, .count = 2};
        case AstNodeIdArity::Many:
            return {.ptr = nodeRefs_.ptr(n.slice.index), .count = n.slice.count};
    }

    return {};
}

SWC_END_NAMESPACE();
