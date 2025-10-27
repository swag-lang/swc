#include "pch.h"

#include "AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    auto [r, p] = store_.emplace_uninit<AstNodeBlock>();
    p->id       = id;
    p->flags    = 0;
    p->token    = token;
    p->children = store_.push_span(span);

    return r;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef openToken, TokenRef closeToken, const std::span<AstNodeRef>& span)
{
    auto [r, p]   = store_.emplace_uninit<AstNodeDelimitedBlock>();
    p->id         = id;
    p->flags      = 0;
    p->token      = openToken;
    p->closeToken = closeToken;
    p->children   = store_.push_span(span);

    return r;
}

SWC_END_NAMESPACE();
