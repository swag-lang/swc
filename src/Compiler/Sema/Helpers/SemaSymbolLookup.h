#pragma once
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace SemaSymbolLookup
{
    template<typename T>
    inline bool hasConcreteFunctionCandidate(std::span<T> symbols)
    {
        for (T const sym : symbols)
        {
            if (!sym || !sym->isFunction())
                continue;

            const auto& fn = sym->cast<SymbolFunction>();
            if (!fn.isEmpty())
                return true;
        }

        return false;
    }

    template<typename T>
    inline void removeEmptyFunctionDeclarations(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        outSymbols.clear();
        outSymbols.reserve(inSymbols.size());

        if (!hasConcreteFunctionCandidate(inSymbols))
        {
            for (T const sym : inSymbols)
            {
                if (sym)
                    outSymbols.push_back(sym);
            }

            return;
        }

        for (T const sym : inSymbols)
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

    template<typename T>
    inline bool filterCallCalleeCandidates(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        outSymbols.clear();

        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        for (T const sym : inSymbols)
        {
            if (sym && sym->isFunction())
                outSymbols.push_back(sym);
        }

        return !outSymbols.empty();
    }

    template<typename T>
    inline Result bindResolvedSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<T> foundSymbols)
    {
        SmallVector<T> filteredSymbols;
        removeEmptyFunctionDeclarations(foundSymbols, filteredSymbols);

        SmallVector<T> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        if (runtimeSymbols.size() <= 1)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols.span());
            return Result::Continue;
        }

        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols);

        SmallVector<T> callables;
        if (filterCallCalleeCandidates(runtimeSymbols.span(), callables))
        {
            sema.setSymbolList(nodeRef, callables.span());
            return Result::Continue;
        }

        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols.span());
    }

    template<typename T>
    inline Result bindSymbolList(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<T> symbols)
    {
        SmallVector<T> filteredSymbols;
        removeEmptyFunctionDeclarations(symbols, filteredSymbols);

        SmallVector<T> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        if (runtimeSymbols.size() <= 1 || !allowOverloadSetForCallCallee)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols.span());
            return Result::Continue;
        }

        SmallVector<T> callables;
        if (filterCallCalleeCandidates(runtimeSymbols.span(), callables))
            sema.setSymbolList(nodeRef, callables.span());
        else
            sema.setSymbolList(nodeRef, runtimeSymbols.span());

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
