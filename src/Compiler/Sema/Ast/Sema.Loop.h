#pragma once
#include "Compiler/Sema/Core/NodePayload.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class Symbol;

struct LoopSemaPayload
{
    TypeRef                           indexTypeRef = TypeRef::invalid();
    ConstantRef                       countCstRef  = ConstantRef::invalid();
    SymbolFunction*                   countFn      = nullptr;
    SmallVector<ResolvedCallArgument> countResolvedArgs;
    AstNodeRef                        lowerBoundRef   = AstNodeRef::invalid();
    AstNodeRef                        upperBoundRef   = AstNodeRef::invalid();
    bool                              usesCustomVisit = false;
    bool                              isRangeLoop     = false;
    bool                              inclusive       = false;
    bool                              usesLoopIndex   = false;
    SmallVector<Symbol*>              localSymbols;
};

SWC_END_NAMESPACE();
