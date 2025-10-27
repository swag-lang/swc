#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token)
{
    return nodes_.emplace_back<AstNode>(id, token) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenOne& kids)
{
    return nodes_.emplace_back<AstNode>(id, token, kids) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenTwo& kids)
{
    return nodes_.emplace_back<AstNode>(id, token, kids) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenMany& kids)
{
    return nodes_.emplace_back<AstNode>(id, token, kids) + 1;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : span)
        nodeRefs_.emplace_back<AstNodeRef>(s);
    return makeNode(id, token, AstChildrenMany{.index = first, .count = static_cast<uint32_t>(span.size())});
}

SWC_END_NAMESPACE();
