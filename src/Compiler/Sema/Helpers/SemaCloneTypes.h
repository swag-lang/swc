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
        TypeRef       typeRef            = TypeRef::invalid();
        ConstantRef   cstRef             = ConstantRef::invalid();
        bool          forceMaterialize   = false;
        bool          preserveUseCodeRef = false;
        // The binding was homed into a mutable 'var' copy for an ordinary inline: its
        // uses are the callee's own local, not the caller's expression, so they are NOT
        // const-assignment targets.
        bool                  mutableHomeUse = false;
        const SymbolVariable* sourceParam    = nullptr;
    };
}

SWC_END_NAMESPACE();
