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
        {
            const auto& o = std::get<AstChildrenOne>(n.children);
            return {.ptr = &o.first, .count = 1};
        }
        case AstNodeIdArity::Two:
        {
            const auto& o = std::get<AstChildrenTwo>(n.children);
            return {.ptr = &o.first, .count = 2};
        }

        case AstNodeIdArity::Many:
        {
            const auto& o = std::get<AstChildrenMany>(n.children);
            return {.ptr = nodeRefs_.ptr(o.index), .count = o.count};
        }
    }

    return {};
}

SWC_END_NAMESPACE();
