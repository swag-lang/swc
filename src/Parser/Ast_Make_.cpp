#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token)
{
    return nodes_.emplace_back(id, token) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenOne& kids)
{
    return nodes_.emplace_back(id, token, kids) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenTwo& kids)
{
    return nodes_.emplace_back(id, token, kids) + 1;
}

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, const AstChildrenSlice& kids)
{
    return nodes_.emplace_back(id, token, kids) + 1;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::vector<AstNodeRef>& stmts)
{
    const uint32_t first = nodeRefs_.size();
    for (auto s : stmts)
        nodeRefs_.emplace_back(s);
    return makeNode(id, token, AstChildrenSlice{.index = first, .count = static_cast<uint32_t>(stmts.size())});
}

SWC_END_NAMESPACE();
