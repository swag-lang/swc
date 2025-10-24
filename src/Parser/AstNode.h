#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

enum class AstNodeId : uint16_t
{
    Invalid = 0,
    File,
};

enum class AstNodeFlagsEnum : uint16_t
{
    Zero = 0,
};

using AstNodeFlags = Flags<AstNodeFlagsEnum>;

struct AstNode
{
    AstNodeId    id     = AstNodeId::Invalid;
    AstNodeFlags flags  = AstNodeFlagsEnum::Zero;
    FileRef      file   = INVALID_FILE_REF;
    TokenRef     token  = INVALID_TOKEN_REF;
    AstNodeRef   parent = INVALID_AST_NODE_REF;
    AstNodeRef   left   = INVALID_AST_NODE_REF;
    AstNodeRef   right  = INVALID_AST_NODE_REF;
};

SWC_END_NAMESPACE();
