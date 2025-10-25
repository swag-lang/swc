#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeNode(AstNodeId id, TokenRef token, AstPayloadKind payloadKind, AstPayloadRef payloadRef)
{
    return nodes_.emplace_back(id, AstNodeFlagsEnum::Zero, token, payloadKind, payloadRef) + 1;
}

AstNodeRef Ast::makeBlock(AstNodeId id, TokenRef token, const std::vector<AstNodeRef>& stmts)
{
    const AstNodeRef first = nodeRefs_.size();
    for (auto s : stmts)
        nodeRefs_.emplace_back(s);
    const auto sid = sliceStore_.emplace_back(AstPayLoad::SliceKids{.first = first, .count = static_cast<uint32_t>(stmts.size())});
    return makeNode(id, token, AstPayloadKind::SliceKids, sid);
}

SWC_END_NAMESPACE();
