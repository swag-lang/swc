#pragma once
#include "Core/Types.h"
#include "Memory/PagedStore.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
protected:
    friend class Parser;
    Arena                  arena_;
    PagedStore<AstNode>    nodes_{arena_};
    PagedStore<AstNodeRef> nodeRefs_{arena_};
    AstNodeRef             root_ = INVALID_REF;

    PagedStore<AstPayLoad::SliceKids> sliceStore_{arena_};

public:
    AstNode*       node(AstNodeRef ref) { return nodes_.ptr(ref); }
    const AstNode* node(AstNodeRef ref) const { return nodes_.ptr(ref); }

    // Produce a uniform ChildrenView regardless of payload kind.
    AstNodeChildrenView children(const AstNode& n) const
    {
        switch (n.payloadKind)
        {
            case AstPayloadKind::SliceKids:
            {
                const auto& sl = sliceStore_.at(n.payloadRef);
                return {.ptr = nodeRefs_.ptr(sl.first), .n = sl.count};
            }
            default:
                return {};
        }
    }

    AstNodeRef makeNode(AstNodeId id, FileRef file, TokenRef token = INVALID_REF, AstPayloadKind payloadKind = AstPayloadKind::Invalid, AstPayloadRef payloadRef = INVALID_REF)
    {
        return nodes_.emplace_back(id, AstNodeFlagsEnum::Zero, file, token, payloadKind, payloadRef);
    }

    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::vector<AstNodeRef>& stmts)
    {
        const AstNodeRef first = nodeRefs_.size();
        for (auto s : stmts)
            nodeRefs_.emplace_back(s);
        const auto sid = sliceStore_.emplace_back(AstPayLoad::SliceKids{.first = first, .count = static_cast<uint32_t>(stmts.size())});
        return makeNode(id, 0, token, AstPayloadKind::SliceKids, sid);
    }
};

SWC_END_NAMESPACE();
