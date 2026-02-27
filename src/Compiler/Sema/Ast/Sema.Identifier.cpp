#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasConcreteFunctionCandidate(std::span<const Symbol*> symbols)
    {
        for (const Symbol* const sym : symbols)
        {
            if (!sym || !sym->isFunction())
                continue;
            const auto& fn = sym->cast<SymbolFunction>();
            if (!fn.isEmpty())
                return true;
        }

        return false;
    }

    void removeEmptyFunctionDeclarations(std::span<const Symbol*> inSymbols, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();
        outSymbols.reserve(inSymbols.size());

        if (!hasConcreteFunctionCandidate(inSymbols))
        {
            for (const Symbol* const sym : inSymbols)
            {
                if (sym)
                    outSymbols.push_back(sym);
            }
            return;
        }

        for (const Symbol* const sym : inSymbols)
        {
            if (!sym)
                continue;
            if (sym->isFunction())
            {
                const auto& fn = sym->cast<SymbolFunction>();
                if (!fn.isForeign() && fn.isEmpty())
                    continue;
            }

            outSymbols.push_back(sym);
        }
    }

    // A call callee may legitimately bind to an overload set, but only for callable candidates.
    // If at least one callable candidate exists, keep ONLY those callables (ignore non-callables for a call).
    // If no callable candidates exist:
    //   - if there are multiple candidates, it's ambiguous in value space (report here)
    //   - if there is exactly one, bind it and let the call expression report "not callable".
    bool filterCallCalleeCandidates(std::span<const Symbol*> inSymbols, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();
        SmallVector<const Symbol*> filteredSymbols;
        removeEmptyFunctionDeclarations(inSymbols, filteredSymbols);

        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        for (const Symbol* const s : filteredSymbols)
        {
            if (s && s->isFunction())
                outSymbols.push_back(s);
        }

        return !outSymbols.empty();
    }

    Result checkAmbiguityAndBindSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<const Symbol*> foundSymbols)
    {
        SmallVector<const Symbol*> filteredSymbols;
        removeEmptyFunctionDeclarations(foundSymbols, filteredSymbols);

        const size_t n = filteredSymbols.size();

        if (n <= 1)
        {
            sema.setSymbolList(nodeRef, filteredSymbols);
            return Result::Continue;
        }

        // Multiple candidates.
        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, filteredSymbols);

        // Call-callee context: keep only callables if any exist.
        SmallVector<const Symbol*> callables;
        if (filterCallCalleeCandidates(filteredSymbols, callables))
        {
            sema.setSymbolList(nodeRef, callables);
            return Result::Continue;
        }

        // No callable candidates and multiple results => true ambiguity (e.g. multiple vars/namespaces/etc.).
        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, filteredSymbols);
    }

}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    const SemaNodeView view = sema.curViewConstant();
    if (view.cstRef().isValid())
        return Result::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), codeRef());

    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    SWC_RESULT_VERIFY(ret);

    SWC_RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
