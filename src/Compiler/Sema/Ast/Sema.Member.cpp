#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A call callee may legitimately bind to an overload set, but only for callable candidates.
    // If at least one callable candidate exists, keep ONLY those callables (ignore non-callables for a call).
    // If no callable candidates exist:
    //   - if there are multiple candidates, it's ambiguous in value space (report here)
    //   - if there is exactly one, bind it and let the call expression report "not callable".
    bool filterCallCalleeCandidates(std::span<const Symbol*> inSymbols, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();

        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        for (const Symbol* s : inSymbols)
        {
            if (s && s->isFunction())
                outSymbols.push_back(s);
        }

        return !outSymbols.empty();
    }

    Result checkAmbiguityAndBindSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<const Symbol*> foundSymbols)
    {
        const size_t n = foundSymbols.size();

        if (n <= 1)
        {
            sema.setSymbolList(nodeRef, foundSymbols);
            return Result::Continue;
        }

        // Multiple candidates.
        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);

        // Call-callee context: keep only callables if any exist.
        SmallVector<const Symbol*> callables;
        if (filterCallCalleeCandidates(foundSymbols, callables))
        {
            sema.setSymbolList(nodeRef, callables);
            return Result::Continue;
        }

        // No callable candidates and multiple results => true ambiguity (e.g. multiple vars/namespaces/etc.).
        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);
    }

    void bindMemberSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSet, std::span<const Symbol*> symbols)
    {
        if (symbols.size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRef, symbols);
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(symbols, callables))
                sema.setSymbolList(nodeRef, callables);
            else
                sema.setSymbolList(nodeRef, symbols);
        }
    }
}

namespace
{
    Result memberNamespace(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &namespaceSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result memberEnum(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum& enumSym = nodeLeftView.type->payloadSymEnum();
        RESULT_VERIFY(sema.waitCompleted(&enumSym, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &enumSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result memberInterface(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type->payloadSymInterface();
        RESULT_VERIFY(sema.waitCompleted(&symInterface, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef = SourceCodeRef{node->srcViewRef(), tokNameRef};

        if (nodeLeftView.sym && nodeLeftView.sym->isImpl())
            lookUpCxt.symMapHint = nodeLeftView.sym->asSymMap();
        else
            lookUpCxt.symMapHint = &symInterface;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result memberStruct(Sema& sema, AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo* typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo->payloadSymStruct();
        RESULT_VERIFY(sema.waitCompleted(&symStruct, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symStruct;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        // Constant struct member access
        const auto finalSymCount = sema.getSymbolList(node->nodeRightRef).size();
        if (nodeLeftView.cst && finalSymCount == 1 && sema.getSymbolList(node->nodeRightRef)[0]->isVariable())
        {
            const SymbolVariable& symVar = sema.getSymbolList(node->nodeRightRef)[0]->cast<SymbolVariable>();
            RESULT_VERIFY(ConstantExtract::structMember(sema, *nodeLeftView.cst, symVar, sema.curNodeRef(), node->nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference() || sema.isLValue(node->nodeLeftRef))
            sema.setIsLValue(*node);
        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, const TypeInfo* typeInfo)
    {
        const auto& aggregate = typeInfo->payloadAggregate();
        const auto& names     = aggregate.names;
        const auto& types     = aggregate.types;
        SWC_ASSERT(names.size() == types.size());

        size_t memberIndex = 0;
        bool   found       = false;

        const std::string_view idName = sema.idMgr().get(idRef).name;
        for (size_t i = 0; i < names.size(); ++i)
        {
            if (names[i].isValid())
            {
                if (names[i] == idRef)
                {
                    memberIndex = i;
                    found       = true;
                    break;
                }
            }
            else if (idName == ("item" + std::to_string(i)))
            {
                memberIndex = i;
                found       = true;
                break;
            }
        }

        if (!found)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_symbol, SourceCodeRef{node->srcViewRef(), tokNameRef});
            diag.addArgument(Diagnostic::ARG_SYM, idRef);
            diag.report(sema.ctx());
            return Result::SkipChildren;
        }

        const TypeRef memberTypeRef = types[memberIndex];
        sema.setType(sema.curNodeRef(), memberTypeRef);
        sema.setType(node->nodeRightRef, memberTypeRef);
        sema.setIsValue(*node);
        sema.setIsValue(node->nodeRightRef);

        const auto& values = nodeLeftView.cst->getAggregateStruct();
        SWC_ASSERT(memberIndex < values.size());
        sema.setConstant(sema.curNodeRef(), values[memberIndex]);
        return Result::SkipChildren;
    }
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    // Parser tags the callee expression when building a call: `a.foo()`.
    const bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);

    SemaNodeView        nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView  nodeRightView(sema, nodeRightRef);
    const TokenRef      tokNameRef = nodeRightView.node->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node->codeRef());
    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
        return memberNamespace(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    SWC_ASSERT(nodeLeftView.type);

    // Enum
    if (nodeLeftView.type->isEnum())
        return memberEnum(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type->isInterface())
        return memberInterface(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type->isAggregateStruct())
        return memberAggregateStruct(sema, this, nodeLeftView, idRef, tokNameRef, nodeLeftView.type);

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        RESULT_VERIFY(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));
        typeInfo = &sema.typeMgr().get(sema.typeMgr().structTypeInfo());
    }
    else if (typeInfo->isTypeInfo())
    {
        const TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (typeInfoRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().predefined(IdentifierManager::PredefinedName::TypeInfo), {srcViewRef(), tokNameRef});
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer() || typeInfo->isReference())
    {
        typeInfo = &sema.typeMgr().get(typeInfo->payloadTypeRef());
    }

    // Struct
    if (typeInfo->isStruct())
        return memberStruct(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet, typeInfo);

    // Pointer/Reference
    if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference())
    {
        sema.setType(sema.curNodeRef(), nodeLeftView.type->payloadTypeRef());
        sema.setIsValue(*this);
        return Result::SkipChildren;
    }

    return SemaError::raiseInternal(sema, sema.curNodeRef());
}

SWC_END_NAMESPACE();
