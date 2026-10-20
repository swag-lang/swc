#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

namespace SemaClone
{
    struct ParamBinding
    {
        IdentifierRef idRef;
        AstNodeRef    exprRef;
        TypeRef       typeRef = TypeRef::invalid();
        ConstantRef   cstRef  = ConstantRef::invalid();

        bool forceMaterialize   = false;
        bool preserveUseCodeRef = false;

        // A mutable var home is the callee's local copy, not the caller's expression,
        // so its uses are not const-assignment targets.
        bool mutableHomeUse = false;

        const SymbolVariable* sourceParam        = nullptr;
        AstNodeRef            valueBorrowHomeRef = AstNodeRef::invalid();

        // The home addresses storage built for this call alone, which nothing else can write.
        bool valueBorrowFreshStorage = false;
    };
}

SWC_END_NAMESPACE();
