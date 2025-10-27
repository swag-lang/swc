#include "pch.h"

#include "AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.push_back<AstNodeRef>(s);

    AstNodeBlock cmp{id, token};
    cmp.firstChild  = first;
    cmp.numChildren = static_cast<uint32_t>(span.size());
    return makeNode<AstNodeBlock>(cmp);
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span, TokenRef closeToken)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.push_back<AstNodeRef>(s);

    AstNodeDelimitedBlock cmp{id, token};
    cmp.closeToken  = closeToken;
    cmp.firstChild  = first;
    cmp.numChildren = static_cast<uint32_t>(span.size());
    return makeNode<AstNodeDelimitedBlock>(cmp);
}

SWC_END_NAMESPACE();
