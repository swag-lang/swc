#pragma once
#include "Compiler/Sema/Core/NodePayload.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

struct LoopSemaPayload
{
    TypeRef                           indexTypeRef = TypeRef::invalid();
    ConstantRef                       countCstRef  = ConstantRef::invalid();
    SymbolFunction*                   countFn      = nullptr;
    SmallVector<ResolvedCallArgument> countResolvedArgs;
    AstNodeRef                        lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef                        upperBoundRef = AstNodeRef::invalid();
    bool                              isRangeLoop   = false;
    bool                              inclusive     = false;
    bool                              usesLoopIndex = false;
};

SWC_END_NAMESPACE();
