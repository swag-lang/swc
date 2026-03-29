#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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
        if (!(symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
              symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
              symVar.isClosureCapture()))
            return false;

        return true;
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

    if (sema.curViewType().typeRef().isValid())
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isValid())
        {
            const AstNode& parentNode = sema.node(parentRef);
            if (parentNode.is(AstNodeId::NamedType) || parentNode.is(AstNodeId::QuotedExpr) || parentNode.is(AstNodeId::QuotedListExpr))
                return Result::Continue;

            // Generic specialization can clone a type parameter into a plain identifier and
            // pre-seed its resolved type (for example in `#sizeof(T)`). Only skip lookup in
            // compiler intrinsics that accept a type-only operand; declaration identifiers
            // still need normal symbol binding even if their final type has already been set.
            if (!sema.curViewSymbol().sym() && !sema.curViewSymbolList().hasSymbolList())
            {
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
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    SWC_RESULT(ret);

    SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols().span()));
    if (const Symbol* sym = sema.curViewSymbol().sym(); sym && requiresExplicitClosureCapture(sema, *sym))
        return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_missing, sema.curNodeRef());
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
