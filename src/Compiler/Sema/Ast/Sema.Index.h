#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

enum class IndexSpecOpPayloadKind : uint8_t
{
    None,
    Read,
    DeferredAssign,
};

struct IndexSpecOpPayloadBase
{
    IndexSpecOpPayloadKind kind = IndexSpecOpPayloadKind::None;
};

struct SliceIndexSemaPayload
{
    AstNodeRef lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef upperBoundRef = AstNodeRef::invalid();
    bool       inclusive     = false;
};

struct IndexSpecOpSemaPayload : IndexSpecOpPayloadBase
{
    IndexSpecOpSemaPayload()
    {
        kind = IndexSpecOpPayloadKind::Read;
    }

    SymbolFunction* calledFn = nullptr;
};

SWC_END_NAMESPACE();
