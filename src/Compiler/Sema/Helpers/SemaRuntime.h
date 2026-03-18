#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace SemaRuntime
{
    inline bool isNativeArtifactCompilerFunction(const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::CompilerFuncTest:
            case TokenId::CompilerFuncInit:
            case TokenId::CompilerFuncDrop:
            case TokenId::CompilerFuncMain:
            case TokenId::CompilerFuncPreMain:
                return true;

            default:
                return false;
        }
    }

    inline const SymbolFunction* transparentLocationFunction(const SymbolFunction* function)
    {
        while (function)
        {
            const AstNode* const decl = function->decl();
            if (!decl || decl->id() != AstNodeId::CompilerFunc)
                return function;

            const SymbolMap* const ownerMap = function->ownerSymMap();
            const auto* const      ownerFn  = ownerMap ? ownerMap->safeCast<SymbolFunction>() : nullptr;
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

        const AstNode* const decl = symbol.decl();
        if (!decl)
            return false;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return true;
        if (decl->id() != AstNodeId::CompilerFunc)
            return false;

        const TokenId tokenId = sema.srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return !isNativeArtifactCompilerFunction(tokenId);
    }

    inline bool isCompilerOnlyVariable(const SymbolVariable& symbol)
    {
        return symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    inline bool isCompilerOnlySymbol(const Sema& sema, const Symbol& symbol)
    {
        if (const auto* const function = symbol.safeCast<SymbolFunction>())
            return isCompilerOnlyFunction(sema, *function);
        if (const auto* const variable = symbol.safeCast<SymbolVariable>())
            return isCompilerOnlyVariable(*variable);
        return false;
    }

    inline bool isRuntimeArtifactFunction(const Sema& sema, const SymbolFunction& symbol)
    {
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return false;

        const AstNode* const decl = symbol.decl();
        if (!decl)
            return true;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return false;
        if (decl->id() != AstNodeId::CompilerFunc)
            return true;

        const TokenId tokenId = sema.srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return isNativeArtifactCompilerFunction(tokenId);
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
                return !isNativeArtifactCompilerFunction(tokenId);
            }

            default:
                return false;
        }
    }

    inline bool hasCompilerEvalAstContext(const Sema& sema)
    {
        if (isCompilerEvalContextNode(sema, sema.curNode()))
            return true;

        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                break;
            if (isCompilerEvalContextNode(sema, sema.node(parentRef)))
                return true;
        }

        return false;
    }

    inline bool isRuntimeArtifactContext(const Sema& sema)
    {
        if (SemaHelpers::isRunExprContext(sema))
            return false;
        if (SemaHelpers::isConstExprRequired(sema))
            return false;
        if (hasCompilerEvalAstContext(sema))
            return false;

        const SymbolFunction* const currentFunction = sema.frame().currentFunction();
        return currentFunction != nullptr && isRuntimeArtifactFunction(sema, *currentFunction);
    }

    template<typename T>
    Result filterRuntimeAccessibleSymbols(Sema& sema, AstNodeRef nodeRef, std::span<T> inSymbols, SmallVector<T>& outSymbols)
    {
        outSymbols.clear();
        outSymbols.reserve(inSymbols.size());

        const bool    runtimeContext     = isRuntimeArtifactContext(sema);
        const Symbol* compilerOnlySymbol = nullptr;
        for (T symbol : inSymbols)
        {
            if (!symbol)
                continue;

            const auto* baseSymbol = static_cast<const Symbol*>(symbol);
            if (runtimeContext && isCompilerOnlySymbol(sema, *baseSymbol))
            {
                if (!compilerOnlySymbol)
                    compilerOnlySymbol = baseSymbol;
                continue;
            }

            outSymbols.push_back(symbol);
        }

        if (!outSymbols.empty() || !compilerOnlySymbol)
            return Result::Continue;

        return SemaError::raiseRuntimeUsesCompilerOnlySymbol(sema, nodeRef, *compilerOnlySymbol);
    }
}

SWC_END_NAMESPACE();
