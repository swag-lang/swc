#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool containsInlineBindingUse(Sema& sema, AstNodeRef nodeRef, std::span<const SemaClone::ParamBinding> bindings)
    {
        if (nodeRef.isInvalid() || bindings.empty())
            return false;

        const AstNode& node = sema.node(nodeRef);
        if (const auto* ident = node.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            for (const SemaClone::ParamBinding& binding : bindings)
            {
                if (binding.idRef == idRef)
                    return true;
            }
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (containsInlineBindingUse(sema, childRef, bindings))
                return true;
        }

        return false;
    }

    using SemaHelpers::resolveLambdaBindingFunction;

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

    bool requiresExplicitClosureCapture(Sema& sema, const Symbol& symbol)
    {
        const SymbolFunction* currentFn = sema.currentFunction();
        if (!currentFn || !requiresExplicitCaptureList(sema, *currentFn))
            return false;

        const AstIdentifier& node = sema.curNode().cast<AstIdentifier>();
        if (node.hasFlag(AstIdentifierFlagsE::InClosureCapture))
            return false;

        if (!symbol.isVariable())
            return false;

        const auto& symVar = symbol.cast<SymbolVariable>();
        if (symVar.ownerSymMap() == currentFn)
            return false;
        if (symVar.hasGlobalStorage())
            return false;

        // Local-scope variables (e.g. inside a block or foreach body) have no
        // ownerSymMap, so ownerFunction() cannot walk the scope chain. Check
        // the function's local variable list directly.
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        {
            const auto& locals = currentFn->localVariables();
            if (std::ranges::find(locals, &symVar) != locals.end())
                return false;
        }

        if (symVar.isFunctionLocalVariable(*currentFn))
            return false;

        if (!(symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
              symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
              symVar.isClosureCapture()))
            return false;

        return true;
    }

    bool isCurrentImplFamilySymbol(const SymbolImpl& currentImpl, const Symbol& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        if (!owner)
            return false;
        if (owner == static_cast<const SymbolMap*>(&currentImpl))
            return true;

        if (currentImpl.isForStruct())
        {
            const SymbolStruct* target = currentImpl.symStruct();
            if (!target)
                return false;
            if (owner->isStruct())
                return &owner->cast<SymbolStruct>() == target;
            if (!owner->isImpl())
                return false;
            const auto& ownerImpl = owner->cast<SymbolImpl>();
            return ownerImpl.isForStruct() && ownerImpl.symStruct() == target;
        }

        if (currentImpl.isForEnum())
        {
            const SymbolEnum* target = currentImpl.symEnum();
            if (!target)
                return false;
            if (owner->isEnum())
                return &owner->cast<SymbolEnum>() == target;
            if (!owner->isImpl())
                return false;
            const auto& ownerImpl = owner->cast<SymbolImpl>();
            return ownerImpl.isForEnum() && ownerImpl.symEnum() == target;
        }

        return false;
    }

    bool subtreeContains(Sema& sema, AstNodeRef rootRef, AstNodeRef needleRef)
    {
        if (rootRef.isInvalid())
            return false;
        if (rootRef == needleRef)
            return true;

        SmallVector<AstNodeRef> children;
        sema.node(rootRef).collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (subtreeContains(sema, childRef, needleRef))
                return true;
        }

        return false;
    }

    bool isSwagOperatorsAttributeCall(Sema& sema, const AstCallExpr& call)
    {
        if (!call.hasFlag(AstCallExprFlagsE::AttributeContext))
            return false;

        SmallVector<Symbol*> calleeSymbols;
        sema.viewNodeSymbolList(call.nodeExprRef).getSymbols(calleeSymbols);
        const IdentifierRef operatorsId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Operators);
        for (const Symbol* symbol : calleeSymbols)
        {
            if (!symbol || !symbol->isFunction())
                continue;

            const auto& function = symbol->cast<SymbolFunction>();
            if (function.idRef() == operatorsId && function.isAttribute() && function.inSwagNamespace(sema.ctx()))
                return true;
        }

        return false;
    }

    bool isBareSwagOperatorsArgument(Sema& sema)
    {
        const AstNodeRef currentRef = sema.curNodeRef();
        for (size_t up = 0;; ++up)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(up);
            if (parentRef.isInvalid())
                return false;

            const AstNode& parent = sema.node(parentRef);
            if (const auto* call = parent.safeCast<AstCallExpr>())
            {
                if (subtreeContains(sema, call->nodeExprRef, currentRef))
                    return false;
                return isSwagOperatorsAttributeCall(sema, *call);
            }
        }
    }

    bool trySetSwagOperatorsNameConstant(Sema& sema, const AstIdentifier& node)
    {
        if (!node.codeRef().isValid())
            return false;

        const std::string_view operatorName = sema.tokenString(node.codeRef());
        if (!LangSpec::isSpecOpName(operatorName))
            return false;
        if (!isBareSwagOperatorsArgument(sema))
            return false;

        const ConstantValue constant = ConstantValue::makeString(sema.ctx(), operatorName);
        const ConstantRef   cstRef   = sema.cstMgr().addConstant(sema.ctx(), constant);
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeString());
        sema.setConstant(sema.curNodeRef(), cstRef);
        sema.setIsValue(sema.curNode());
        sema.unsetIsLValue(sema.curNodeRef());
        return true;
    }

    template<typename T>
    bool shouldWaitForPendingImplOverloads(Sema& sema, const bool allowOverloadSet, std::span<T> symbols)
    {
        if (!allowOverloadSet)
            return false;
        if (sema.compiler().pendingImplRegistrations() == 0)
            return false;

        const SymbolImpl* currentImpl = sema.frame().currentImpl();
        if (!currentImpl)
            return false;

        bool hasCurrentImplFamilyCandidate = false;
        for (const Symbol* symbol : symbols)
        {
            if (!symbol || !symbol->acceptOverloads())
                return false;
            if (isCurrentImplFamilySymbol(*currentImpl, *symbol))
                hasCurrentImplFamilyCandidate = true;
        }

        return hasCurrentImplFamilyCandidate;
    }

    void collectQuotedGenericArgs(const Sema& sema, const AstQuotedExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        SWC_UNUSED(sema);
        outArgs.clear();
        if (node.nodeSuffixRef.isValid())
            outArgs.push_back(node.nodeSuffixRef);
    }

    void collectQuotedGenericArgs(Sema& sema, const AstQuotedListExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        outArgs.clear();
        sema.ast().appendNodes(outArgs, node.spanChildrenRef);
    }

    template<typename T>
    Result semaQuotedGenericCommon(Sema& sema, const T& node)
    {
        SmallVector<AstNodeRef> genericArgs;
        collectQuotedGenericArgs(sema, node, genericArgs);

        SmallVector<Symbol*> baseSymbols;
        sema.viewNodeSymbolList(node.nodeExprRef).getSymbols(baseSymbols);

        SmallVector<Symbol*> specializedFunctions;
        SymbolStruct*        specializedStruct = nullptr;
        bool                 sawFunction       = false;
        bool                 sawStruct         = false;

        for (Symbol* baseSym : baseSymbols)
        {
            if (!baseSym)
                continue;

            if (baseSym->isFunction())
            {
                sawFunction = true;
                auto& fn    = baseSym->cast<SymbolFunction>();

                SymbolFunction* instance = nullptr;
                SWC_RESULT(SemaGeneric::instantiateFunctionExplicit(sema, fn, genericArgs.span(), instance));
                if (instance)
                    specializedFunctions.push_back(instance);
            }
            else if (baseSym->isStruct())
            {
                sawStruct = true;
                auto& st  = baseSym->cast<SymbolStruct>();
                if (!st.isGenericRoot())
                    continue;

                SymbolStruct* instance = nullptr;
                SWC_RESULT(SemaGeneric::instantiateStructExplicit(sema, st, genericArgs.span(), instance));
                if (instance)
                {
                    if (specializedStruct && specializedStruct != instance)
                    {
                        SmallVector<const Symbol*> ambiguous;
                        ambiguous.push_back(specializedStruct);
                        ambiguous.push_back(instance);
                        return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), ambiguous.span());
                    }
                    specializedStruct = instance;
                }
            }
        }

        if (!specializedFunctions.empty())
        {
            if (specializedFunctions.size() == 1)
            {
                sema.setSymbol(sema.curNodeRef(), specializedFunctions.front());
            }
            else
            {
                sema.setSymbolList(sema.curNodeRef(), specializedFunctions.span());
            }

            return Result::Continue;
        }

        if (specializedStruct)
        {
            sema.setSymbol(sema.curNodeRef(), specializedStruct);
            return Result::Continue;
        }

        if (sawStruct)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, sema.curNodeRef());
        if (sawFunction)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_callable, sema.curNodeRef());

        return SemaError::raise(sema, DiagnosticId::sema_err_not_type, sema.curNodeRef());
    }

}

Result AstAncestorIdentifier::semaPreNode(Sema& sema) const
{
    if (nodeValueRef.isValid() || nodeIdentRef.isInvalid())
        return Result::Continue;

    AstNodeRef targetRef         = nodeIdentRef;
    bool       usedInlineBinding = false;
    if (const auto* inlinePayload = sema.frame().currentInlinePayload();
        inlinePayload &&
        containsInlineBindingUse(sema, nodeIdentRef, inlinePayload->argMappings.span()))
    {
        const SemaClone::CloneContext cloneContext{inlinePayload->argMappings.span()};
        targetRef = SemaClone::cloneAst(sema, nodeIdentRef, cloneContext);
        if (targetRef.isInvalid())
            return Result::Error;
        usedInlineBinding = true;
    }

    auto* lookupScope = usedInlineBinding ? sema.lookupScope() : sema.resolvedUpLookupScope();
    if (lookupScope)
    {
        auto frame = sema.frame();
        Sema::configureLookupFrame(frame, lookupScope, true);
        sema.pushFramePopOnPostNode(frame, targetRef);
    }

    sema.setSubstitute(sema.curNodeRef(), targetRef);
    sema.visit().restartCurrentNode(targetRef);
    return Result::Continue;
}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    const SemaNodeView view = sema.curViewConstant();
    if (view.cstRef().isValid())
        return Result::Continue;

    const AstNodeRef parentRef = sema.visit().parentNodeRef();
    if (!sema.curViewSymbol().sym() &&
        !sema.curViewSymbolList().hasSymbolList() &&
        codeRef().isValid() &&
        sema.token(codeRef()).id == TokenId::SymSingleQuote &&
        parentRef.isValid() &&
        sema.node(parentRef).is(AstNodeId::CastExpr))
        return Result::Continue;

    if (parentRef.isValid() && sema.node(parentRef).is(AstNodeId::SuffixLiteral))
        return Result::Continue;

    if (trySetSwagOperatorsNameConstant(sema, *this))
        return Result::Continue;

    if (sema.curViewType().typeRef().isValid())
    {
        if (parentRef.isValid())
        {
            const AstNode& parentNode = sema.node(parentRef);
            if (parentNode.is(AstNodeId::NamedType) ||
                parentNode.is(AstNodeId::QuotedExpr) ||
                parentNode.is(AstNodeId::QuotedListExpr))
                return Result::Continue;

            // Generic specialization can clone a type parameter into a plain identifier and
            // pre-seed its resolved type (for example in `#sizeof(T)`). Only skip lookup in
            // compiler intrinsics that accept a type-only operand; declaration identifiers
            // still need normal symbol binding even if their final type has already been set.
            if (!sema.curViewSymbol().sym() && !sema.curViewSymbolList().hasSymbolList())
            {
                if (hasFlag(AstIdentifierFlagsE::GenericTypeBinding))
                    return Result::Continue;

                if (const auto* compilerCall = parentNode.safeCast<AstCompilerCallOne>())
                {
                    switch (sema.token(compilerCall->codeRef()).id)
                    {
                        case TokenId::CompilerTypeOf:
                        case TokenId::CompilerKindOf:
                        case TokenId::CompilerSizeOf:
                        case TokenId::CompilerAlignOf:
                            return Result::Continue;
                        default:
                            break;
                    }
                }
            }
        }
    }

    const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, codeRef());
    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee) || hasFlag(AstIdentifierFlagsE::InCompilerDefined);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    SWC_RESULT(ret);

    // A call inside an impl can see the current impl before sibling impls have
    // finished registering. Wait once so overload resolution sees the whole set.
    if (shouldWaitForPendingImplOverloads(sema, allowOverloadSet, lookUpCxt.symbols().span()))
        return sema.waitImplRegistrations(idRef, codeRef());

    SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols().span()));
    const Symbol* sym = sema.curViewSymbol().sym();
    if (sym && requiresExplicitClosureCapture(sema, *sym))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_missing, sema.curNodeRef());
        diag.addArgument(Diagnostic::ARG_SYM, sym->name(sema.ctx()));
        if (sym->decl())
        {
            diag.addNote(DiagnosticId::sema_note_capture_source_declared_here);
            diag.last().addArgument(Diagnostic::ARG_SYM, sym->name(sema.ctx()));
            diag.last().addSpan(sym->codeRange(sema.ctx()));
        }
        diag.report(sema.ctx());
        return Result::Error;
    }
    return Result::Continue;
}

Result AstQuotedExpr::semaPostNode(Sema& sema) const
{
    if (sema.hasSubstitute(sema.curNodeRef()))
        return Result::Continue;

    return semaQuotedGenericCommon(sema, *this);
}

Result AstQuotedListExpr::semaPostNode(Sema& sema) const
{
    return semaQuotedGenericCommon(sema, *this);
}

SWC_END_NAMESPACE();
