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

    AstChildrenView children(const AstNode& n) const;

    AstNodeRef makeNode(AstNodeId id, TokenRef token, AstPayloadKind payloadKind = AstPayloadKind::Invalid, AstPayloadRef payloadRef = INVALID_REF);
    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::vector<AstNodeRef>& stmts);
};

SWC_END_NAMESPACE();
