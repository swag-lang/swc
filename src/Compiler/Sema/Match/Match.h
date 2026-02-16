#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
struct ResolvedCallArgument;
class Symbol;
class Sema;
class MatchContext;
class SymbolMap;

namespace Match
{
    Result match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef);
    Result ghosting(Sema& sema, const Symbol& sym);

    Result resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg = AstNodeRef::invalid(), SmallVector<ResolvedCallArgument>* outResolvedArgs = nullptr, bool allowEnumFlagsUnderlying = false);
}

SWC_END_NAMESPACE();
