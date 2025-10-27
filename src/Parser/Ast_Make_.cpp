#include "pch.h"

#include "AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.push_back<AstNodeRef>(s);

    auto [r, p]    = nodes_.emplace_uninit<AstNodeBlock>();
    p->id          = id;
    p->flags       = 0;
    p->token       = token;
    p->firstChild  = first;
    p->numChildren = static_cast<uint32_t>(span.size());

    return r;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef openToken, TokenRef closeToken, const std::span<AstNodeRef>& span)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.push_back<AstNodeRef>(s);

    auto [r, p]    = nodes_.emplace_uninit<AstNodeDelimitedBlock>();
    p->id          = id;
    p->flags       = 0;
    p->token       = openToken;
    p->closeToken  = closeToken;
    p->firstChild  = first;
    p->numChildren = static_cast<uint32_t>(span.size());

    return r;
}

SWC_END_NAMESPACE();
