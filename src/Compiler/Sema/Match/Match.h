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
    enum class ResolveCallMode : uint8_t
    {
        Normal,
        AttributeOnly,
    };

    Result match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef);
    Result ghosting(Sema& sema, const Symbol& sym);

    AstNodeRef resolveCallArgumentRef(const Sema& sema, AstNodeRef argRef);
    AstNodeRef resolveCallArgumentValueRef(const Sema& sema, AstNodeRef argRef);
    void       resolveCallArgumentValues(const Sema& sema, SmallVector<AstNodeRef>& outArgs, std::span<const AstNodeRef> args);

    Result resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg = AstNodeRef::invalid(), SmallVector<ResolvedCallArgument>* outResolvedArgs = nullptr, ResolveCallMode mode = ResolveCallMode::Normal);
}

SWC_END_NAMESPACE();
