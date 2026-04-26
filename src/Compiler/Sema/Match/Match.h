#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
struct ResolvedCallArgument;
class Symbol;
class SymbolFunction;
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

    struct FunctionCandidateProbe
    {
        SmallVector<uint8_t> perArgRanks;
        SymbolFunction*      fn              = nullptr;
        uint32_t             usedDefaults    = 0;
        bool                 genericInstance = false;
        bool                 matched         = false;
    };

    Result match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef);
    Result matchCallFallbackSymbols(Sema& sema, const SemaNodeView& nodeCallee, SmallVector<Symbol*>& outSymbols);
    Result ghosting(Sema& sema, const Symbol& sym);

    AstNodeRef resolveCallArgumentRef(Sema& sema, AstNodeRef argRef);
    AstNodeRef resolveCallArgumentValueRef(Sema& sema, AstNodeRef argRef);
    void       resolveCallArgumentValues(Sema& sema, SmallVector<AstNodeRef>& outArgs, std::span<const AstNodeRef> args);

    int    compareFunctionCandidateProbes(const FunctionCandidateProbe& a, const FunctionCandidateProbe& b);
    Result probeFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, FunctionCandidateProbe& outProbe, bool allowNoMatch = false, ResolveCallMode mode = ResolveCallMode::Normal);
    Result resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg = AstNodeRef::invalid(), SmallVector<ResolvedCallArgument>* outResolvedArgs = nullptr, ResolveCallMode mode = ResolveCallMode::Normal);
}

SWC_END_NAMESPACE();
