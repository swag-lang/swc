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
    bool isNonemptyFunctionDeclaration(T symbol, bool hasConcreteFunction)
    {
        if (!symbol)
            return false;
        if (!hasConcreteFunction || !symbol->isFunction())
            return true;

        const auto& fn = symbol->template cast<SymbolFunction>();
        return fn.isForeign() || !fn.isEmpty();
    }

    // Borrow the overload list unless removing an empty declaration requires an owned copy.
    template<typename T>
    std::span<T> filterEmptyFunctionDeclarations(std::span<T> symbols, SmallVector<std::remove_const_t<T>>& storage)
    {
        if (symbols.size() < 2)
        {
            if (!symbols.empty() && !symbols[0])
            {
                storage.clear();
                return storage.span();
            }
            return symbols;
        }

        const bool hasConcreteFunction = hasConcreteFunctionCandidate<T>(symbols);
        if (!hasConcreteFunction)
            return symbols;

        const bool ownsSymbols = symbols.data() == storage.data();
        if (ownsSymbols)
        {
            size_t writeIndex = 0;
            for (const T sym : symbols)
            {
                if (sym->isFunction())
                {
                    const auto& fn = sym->template cast<SymbolFunction>();
                    if (!fn.isForeign() && fn.isEmpty())
                        continue;
                }

                storage[writeIndex++] = sym;
            }
            storage.resize(writeIndex);
            return storage.span();
        }

        storage.clear();
        bool copied = false;
        for (size_t index = 0; index < symbols.size(); ++index)
        {
            const T sym = symbols[index];
            if (sym->isFunction())
            {
                const auto& fn = sym->template cast<SymbolFunction>();
                if (!fn.isForeign() && fn.isEmpty())
                {
                    if (!copied)
                    {
                        storage.reserve(symbols.size());
                        storage.append(symbols.data(), index);
                        copied = true;
                    }
                    continue;
                }
            }

            if (copied)
                storage.push_back(sym);
        }

        return copied ? storage.span() : symbols;
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
        SmallVector<T> runtimeSymbols;
        const bool     hasConcreteFunction = foundSymbols.size() > 1 && hasConcreteFunctionCandidate<T>(foundSymbols);
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, foundSymbols, runtimeSymbols, [hasConcreteFunction](T symbol) { return isNonemptyFunctionDeclaration(symbol, hasConcreteFunction); }));

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
        SmallVector<T> runtimeSymbols;
        const bool     hasConcreteFunction = symbols.size() > 1 && hasConcreteFunctionCandidate<T>(symbols);
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, symbols, runtimeSymbols, [hasConcreteFunction](T symbol) { return isNonemptyFunctionDeclaration(symbol, hasConcreteFunction); }));

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
