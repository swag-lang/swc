#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;

class Symbol;
class Sema;
class MatchContext;
class SymbolMap;

namespace Match
{
    Result match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef);
    Result ghosting(Sema& sema, const Symbol& sym);

    Result resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args);
}

SWC_END_NAMESPACE();
