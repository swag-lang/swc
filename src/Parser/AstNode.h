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

enum class AstPayloadKind : uint16_t
{
    Invalid = 0,
    SliceKids,
};

namespace AstPayLoad
{
    struct SliceKids
    {
        AstNodeRef first;
        uint32_t   count;
    };
}

struct AstNode
{
    AstNodeId    id    = AstNodeId::Invalid;
    AstNodeFlags flags = AstNodeFlagsEnum::Zero;

    FileRef  file  = INVALID_REF;
    TokenRef token = INVALID_REF;

    AstPayloadKind payloadKind = AstPayloadKind::Invalid;
    AstPayloadRef  payloadRef  = INVALID_REF;

    struct ChildrenView
    {
        const AstNodeRef* ptr = nullptr;
        uint32_t          n   = 0;
        const AstNodeRef* begin() const { return ptr; }
        const AstNodeRef* end() const { return ptr + n; }
        size_t            size() const { return n; }
    };
};

SWC_END_NAMESPACE();
