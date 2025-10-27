#include "pch.h"

#include "AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeCompound(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.emplace_back<AstNodeRef>(s);

    AstNodeCompound cmp{id, token};
    cmp.firstChild  = first;
    cmp.numChildren = static_cast<uint32_t>(span.size());
    return makeNode<AstNodeCompound>(cmp);
}

SWC_END_NAMESPACE();
