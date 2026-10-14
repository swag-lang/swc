#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

namespace SemaRuntime
{
    inline const SymbolFunction* transparentLocationFunction(const SymbolFunction* function)
    {
        while (function)
        {
            const AstNode* decl = function->decl();
            if (!decl)
                return function;

            const bool isTransparentCompilerFunction = decl->id() == AstNodeId::CompilerFunc;
            const bool isTransparentCompilerRun      = decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr;
            if (!isTransparentCompilerFunction && !isTransparentCompilerRun)
                return function;

            const SymbolMap*  ownerMap = function->ownerSymMap();
            const auto* const ownerFn  = ownerMap ? ownerMap->safeCast<SymbolFunction>() : nullptr;
            if (!ownerFn)
                return function;

            function = ownerFn;
        }

        return nullptr;
    }

    inline bool isCompilerOnlyFunction(const Sema& sema, const SymbolFunction& symbol)
    {
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return true;

        const AstNode* decl = symbol.decl();
        if (!decl)
            return false;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return true;
        if (decl->id() != AstNodeId::CompilerFunc)
            return false;

        const TokenId tokenId = sema.srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return !Token::isNativeArtifactCompilerFunc(tokenId);
    }

    inline bool isCompilerOnlyVariable(const SymbolVariable& symbol)
    {
        return symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    inline bool isCompilerOnlySymbol(const Sema& sema, const Symbol& symbol)
    {
        if (const auto* function = symbol.safeCast<SymbolFunction>())
            return isCompilerOnlyFunction(sema, *function);
        if (const auto* variable = symbol.safeCast<SymbolVariable>())
            return isCompilerOnlyVariable(*variable);
        return false;
    }

    inline bool isRuntimeArtifactFunction(const Sema& sema, const SymbolFunction& symbol)
    {
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return false;

        const AstNode* decl = symbol.decl();
        if (!decl)
            return true;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return false;
        if (decl->id() != AstNodeId::CompilerFunc)
            return true;

        const TokenId tokenId = sema.srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return Token::isNativeArtifactCompilerFunc(tokenId);
    }

    inline bool isCompilerEvalContextNode(const Sema& sema, const AstNode& node)
    {
        switch (node.id())
        {
            case AstNodeId::CompilerExpression:
            case AstNodeId::CompilerDiagnostic:
            case AstNodeId::CompilerCallOne:
            case AstNodeId::CompilerCall:
            case AstNodeId::CompilerTypeExpr:
            case AstNodeId::CompilerMessageFunc:
            case AstNodeId::CompilerRunBlock:
            case AstNodeId::CompilerRunExpr:
            case AstNodeId::CompilerCodeBlock:
            case AstNodeId::CompilerCodeExpr:
                return true;

            case AstNodeId::CompilerFunc:
            case AstNodeId::CompilerShortFunc:
            {
                const TokenId tokenId = sema.token(node.codeRef()).id;
                return !Token::isNativeArtifactCompilerFunc(tokenId);
            }

            default:
                return false;
        }
    }

    inline bool isRuntimeArtifactContext(const Sema& sema)
    {
        if (sema.frame().ignoreRuntimeAccess())
            return false;
        if (sema.isRunExprContext())
            return false;
        if (sema.isConstExprRequired())
            return false;
        if (sema.isCompilerEvalContext())
            return false;

        const auto* currentFunction = sema.currentFunction();
        return currentFunction != nullptr && isRuntimeArtifactFunction(sema, *currentFunction);
    }

    // Borrow the input until a filter actually removes a symbol.
    template<typename T>
    Result filterRuntimeAccessibleSymbols(Sema& sema, AstNodeRef nodeRef, std::span<T> inSymbols, std::span<T>& outSymbols, SmallVector<std::remove_const_t<T>>& outStorage, auto&& shouldKeep)
    {
        const bool    runtimeContext     = isRuntimeArtifactContext(sema);
        const Symbol* compilerOnlySymbol = nullptr;
        bool          copied             = false;
        outStorage.clear();
        for (size_t index = 0; index < inSymbols.size(); ++index)
        {
            const T symbol = inSymbols[index];
            bool keep = symbol && shouldKeep(symbol);
            if (keep && runtimeContext)
            {
                const auto* baseSymbol = static_cast<const Symbol*>(symbol);
                if (isCompilerOnlySymbol(sema, *baseSymbol))
                {
                    if (!compilerOnlySymbol)
                        compilerOnlySymbol = baseSymbol;
                    keep = false;
                }
            }

            if (!keep)
            {
                if (!copied)
                {
                    outStorage.reserve(inSymbols.size());
                    outStorage.append(inSymbols.data(), index);
                    copied = true;
                }
                continue;
            }

            if (copied)
                outStorage.push_back(symbol);
        }

        outSymbols = copied ? std::span<T>{outStorage.data(), outStorage.size()} : inSymbols;
        if (!outSymbols.empty() || !compilerOnlySymbol)
            return Result::Continue;

        return SemaError::raiseRuntimeUsesCompilerOnlySymbol(sema, nodeRef, *compilerOnlySymbol);
    }

    template<typename T>
    Result filterRuntimeAccessibleSymbols(Sema& sema, AstNodeRef nodeRef, std::span<T> inSymbols, std::span<T>& outSymbols, SmallVector<std::remove_const_t<T>>& outStorage)
    {
        return filterRuntimeAccessibleSymbols(sema, nodeRef, inSymbols, outSymbols, outStorage, [](T) { return true; });
    }

    template<typename T>
    Result filterRuntimeAccessibleSymbols(Sema& sema, AstNodeRef nodeRef, std::span<T> inSymbols, SmallVector<std::remove_const_t<T>>& outSymbols, auto&& shouldKeep)
    {
        std::span<T> filteredSymbols;
        SWC_RESULT(filterRuntimeAccessibleSymbols(sema, nodeRef, inSymbols, filteredSymbols, outSymbols, shouldKeep));
        if (filteredSymbols.data() != outSymbols.data() || filteredSymbols.size() != outSymbols.size())
            outSymbols.assign(filteredSymbols.begin(), filteredSymbols.end());
        return Result::Continue;
    }

    template<typename T>
    Result filterRuntimeAccessibleSymbols(Sema& sema, AstNodeRef nodeRef, std::span<T> inSymbols, SmallVector<std::remove_const_t<T>>& outSymbols)
    {
        return filterRuntimeAccessibleSymbols(sema, nodeRef, inSymbols, outSymbols, [](T) { return true; });
    }
}

SWC_END_NAMESPACE();
