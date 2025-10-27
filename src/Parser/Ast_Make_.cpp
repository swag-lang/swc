#include "pch.h"

#include "AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    auto [r, p] = makeNodePtr<AstNodeBlock>(id, token);
    p->flags    = 0;
    p->children = store_.push_span(span);
    return r;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef openToken, TokenRef closeToken, const std::span<AstNodeRef>& span)
{
    auto [r, p]   = makeNodePtr<AstNodeDelimitedBlock>(id, openToken);
    p->flags      = 0;
    p->closeToken = closeToken;
    p->children   = store_.push_span(span);

    return r;
}

SWC_END_NAMESPACE();
