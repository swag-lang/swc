#pragma once
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

namespace SemaSymbolLookup
{
    template<typename T>
    bool hasConcreteFunctionCandidate(std::span<T> symbols)
    {
        for (const T sym : symbols)
        {
            if (!sym || !sym->isFunction())
                continue;

            const auto& fn = sym->template cast<SymbolFunction>();
            if (!fn.isEmpty())
                return true;
        }

        return false;
    }

    template<typename T>
    void appendNonemptyFunctionDeclarations(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        if (inSymbols.size() == 1)
        {
            // A lone symbol cannot hide an empty declaration behind a concrete function.
            if (inSymbols.front())
                outSymbols.push_back(inSymbols.front());
            return;
        }
        outSymbols.reserve(inSymbols.size());

        if (!hasConcreteFunctionCandidate(inSymbols))
        {
            for (const T sym : inSymbols)
            {
                if (sym)
                    outSymbols.push_back(sym);
            }

            return;
        }

        for (const T sym : inSymbols)
        {
            if (!sym)
                continue;

            if (sym->isFunction())
            {
                const auto& fn = sym->template cast<SymbolFunction>();
                if (!fn.isForeign() && fn.isEmpty())
                    continue;
            }

            outSymbols.push_back(sym);
        }
    }

    template<typename T>
    void removeEmptyFunctionDeclarations(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        outSymbols.clear();
        appendNonemptyFunctionDeclarations(inSymbols, outSymbols);
    }

    template<typename T>
    void filterEmptyFunctionDeclarations(SmallVector<T>& symbols)
    {
        const bool hasConcreteFunction = symbols.size() > 1 && hasConcreteFunctionCandidate<T>(symbols.span());
        size_t     writeIndex          = 0;
        for (const T sym : symbols)
        {
            if (!sym)
                continue;

            if (hasConcreteFunction && sym->isFunction())
            {
                const auto& fn = sym->template cast<SymbolFunction>();
                if (!fn.isForeign() && fn.isEmpty())
                    continue;
            }

            symbols[writeIndex++] = sym;
        }

        symbols.resize(writeIndex);
    }

    template<typename T>
    bool isCallCalleeCandidate(T sym)
    {
        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        return sym && sym->isFunction();
    }

    template<typename T>
    bool filterCallCalleeCandidates(SmallVector<T>& symbols)
    {
        size_t callableCount = 0;
        for (const T sym : symbols)
        {
            if (isCallCalleeCandidate(sym))
                symbols[callableCount++] = sym;
        }

        if (callableCount == 0)
            return false;

        symbols.resize(callableCount);
        return true;
    }

    template<typename T>
    bool appendCallCalleeCandidates(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        for (const T sym : inSymbols)
        {
            if (isCallCalleeCandidate(sym))
                outSymbols.push_back(sym);
        }

        return !outSymbols.empty();
    }

    template<typename T>
    bool filterCallCalleeCandidates(std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        outSymbols.clear();
        return appendCallCalleeCandidates(inSymbols, outSymbols);
    }

    template<typename T>
    Result bindResolvedSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<T> foundSymbols)
    {
        SmallVector<T> filteredSymbols;
        appendNonemptyFunctionDeclarations(foundSymbols, filteredSymbols);

        SmallVector<T> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        if (runtimeSymbols.size() <= 1)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols.span());
            return Result::Continue;
        }

        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols);

        if (filterCallCalleeCandidates(runtimeSymbols))
        {
            sema.setSymbolList(nodeRef, runtimeSymbols.span());
            return Result::Continue;
        }

        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols.span());
    }

    template<typename T>
    Result bindSymbolList(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<T> symbols)
    {
        SmallVector<T> filteredSymbols;
        appendNonemptyFunctionDeclarations(symbols, filteredSymbols);

        SmallVector<T> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        if (runtimeSymbols.size() <= 1 || !allowOverloadSetForCallCallee)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols.span());
            return Result::Continue;
        }

        filterCallCalleeCandidates(runtimeSymbols);
        sema.setSymbolList(nodeRef, runtimeSymbols.span());

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
