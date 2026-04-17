#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

enum class IndexSpecOpPayloadKind : uint8_t
{
    None,
    Read,
    ReadSlice,
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

struct SliceSpecOpSemaPayload : IndexSpecOpPayloadBase
{
    SliceSpecOpSemaPayload()
    {
        kind = IndexSpecOpPayloadKind::ReadSlice;
    }

    SymbolFunction* calledFn     = nullptr;
    SymbolFunction* countFn      = nullptr;
    AstNodeRef       lowerArgRef = AstNodeRef::invalid();
    AstNodeRef       upperArgRef = AstNodeRef::invalid();
    AstNodeRef       lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef       upperBoundRef = AstNodeRef::invalid();
    bool             inclusive     = false;
};

SWC_END_NAMESPACE();
