#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema)
    {
        const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
        for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
        {
            const TypeRef bindingTypeRef = unwrapLambdaBindingType(sema.ctx(), bindingTypes[bindingIndex - 1]);
            if (!bindingTypeRef.isValid())
                continue;

            const TypeInfo& bindingType = sema.typeMgr().get(bindingTypeRef);
            if (bindingType.isFunction())
                return &bindingType.payloadSymFunction();
        }

        return nullptr;
    }

    bool requiresExplicitCaptureList(Sema& sema, const SymbolFunction& function)
    {
        const AstNode* decl = function.decl();
        if (!decl)
            return false;

        if (decl->is(AstNodeId::ClosureExpr))
            return true;
        if (decl->isNot(AstNodeId::FunctionExpr))
            return false;

        const SymbolFunction* bindingFunction = resolveLambdaBindingFunction(sema);
        return bindingFunction && bindingFunction->isClosure();
    }

    bool hasConcreteFunctionCandidate(std::span<const Symbol*> symbols)
    {
        for (const Symbol* sym : symbols)
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
            for (const Symbol* sym : inSymbols)
            {
                if (sym)
                    outSymbols.push_back(sym);
            }
            return;
        }

        for (const Symbol* sym : inSymbols)
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
        for (const Symbol* s : filteredSymbols)
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
        SmallVector<const Symbol*> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        const size_t n = runtimeSymbols.size();

        if (n <= 1)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols);
            return Result::Continue;
        }

        // Multiple candidates.
        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols);

        // Call-callee context: keep only callables if any exist.
        SmallVector<const Symbol*> callables;
        if (filterCallCalleeCandidates(runtimeSymbols, callables))
        {
            sema.setSymbolList(nodeRef, callables);
            return Result::Continue;
        }

        // No callable candidates and multiple results => true ambiguity (e.g. multiple vars/namespaces/etc.).
        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, runtimeSymbols);
    }

    bool requiresExplicitClosureCapture(Sema& sema, const Symbol& symbol)
    {
        const SymbolFunction* currentFn = SemaHelpers::currentFunction(sema);
        if (!currentFn || !requiresExplicitCaptureList(sema, *currentFn))
            return false;

        const AstNode* parent = sema.visit().parentNode();
        if (parent && parent->is(AstNodeId::ClosureArgument))
            return false;

        if (!symbol.isVariable())
            return false;

        const auto& symVar = symbol.cast<SymbolVariable>();
        if (symVar.ownerSymMap() == currentFn)
            return false;
        if (symVar.hasGlobalStorage())
            return false;
        if (!(symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
              symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
              symVar.isClosureCapture()))
            return false;

        return true;
    }

}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    const SemaNodeView view = sema.curViewConstant();
    if (view.cstRef().isValid())
        return Result::Continue;

    const Token&        tok   = sema.token(codeRef());
    const IdentifierRef idRef = Token::isCompilerUniq(tok.id) ? SemaHelpers::resolveUniqIdentifier(sema, tok.id) : sema.idMgr().addIdentifier(sema.ctx(), codeRef());

    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    SWC_RESULT(ret);

    SWC_RESULT(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
    if (const Symbol* sym = sema.curViewSymbol().sym(); sym && requiresExplicitClosureCapture(sema, *sym))
        return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_missing, sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
