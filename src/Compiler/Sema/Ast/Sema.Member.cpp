#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.MemberAccess.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef memberRuntimeStorageTypeRef(Sema& sema)
    {
        SmallVector<uint64_t> dims;
        dims.push_back(8);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), sema.typeMgr().typeU8()));
    }

    Result completeMemberRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    bool needsStructMemberRuntimeStorage(Sema& sema, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView)
    {
        if (SemaHelpers::isGlobalScope(sema))
            return false;
        if (!nodeLeftView.type())
            return false;
        if (nodeLeftView.type()->isReference())
            return false;
        if (!sema.isLValue(node.nodeLeftRef))
            return true;

        const SemaNodeView leftSymbolView = sema.viewSymbol(node.nodeLeftRef);
        if (!leftSymbolView.sym() || !leftSymbolView.sym()->isVariable())
            return false;

        const auto& leftSymVar = leftSymbolView.sym()->cast<SymbolVariable>();
        return leftSymVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
    }

    SymbolVariable& registerUniqueMemberRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const auto          privateName = Utf8("__member_runtime_storage");
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            symMap->addSymbol(ctx, sym, true);
        }

        return *(sym);
    }
}

bool SemaMemberAccess::resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex)
{
    if (!aggregateType.isAggregateStruct())
        return false;

    const auto&            names  = aggregateType.payloadAggregate().names;
    const std::string_view idName = sema.idMgr().get(idRef).name;
    for (size_t i = 0; i < names.size(); ++i)
    {
        if (names[i].isValid() && names[i] == idRef)
        {
            outIndex = i;
            return true;
        }

        if (!names[i].isValid() && idName == ("item" + std::to_string(i)))
        {
            outIndex = i;
            return true;
        }
    }

    return false;
}

namespace
{
    Result bindMatchedMemberSymbols(Sema& sema, AstNodeRef targetNodeRef, AstNodeRef rightNodeRef, bool allowOverloadSet, std::span<const Symbol*> matchedSymbols)
    {
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, targetNodeRef, allowOverloadSet, matchedSymbols));
        SWC_RESULT(SemaSymbolLookup::bindSymbolList(sema, rightNodeRef, allowOverloadSet, matchedSymbols));
        return Result::Continue;
    }

    Result lookupScopedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SymbolMap& symMap, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symMap;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));
        return Result::SkipChildren;
    }

    Result memberNamespace(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym()->cast<SymbolNamespace>();
        return lookupScopedMember(sema, targetNodeRef, node, namespaceSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberEnum(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum& enumSym = nodeLeftView.type()->payloadSymEnum();
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, {node.srcViewRef(), tokNameRef}));
        return lookupScopedMember(sema, targetNodeRef, node, enumSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberInterface(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type()->payloadSymInterface();
        SWC_RESULT(sema.waitSemaCompleted(&symInterface, {node.srcViewRef(), tokNameRef}));

        const SymbolMap& lookupMap = nodeLeftView.sym() && nodeLeftView.sym()->isImpl() ? *nodeLeftView.sym()->asSymMap() : static_cast<const SymbolMap&>(symInterface);
        return lookupScopedMember(sema, targetNodeRef, node, lookupMap, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo.payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&symStruct, {node.srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symStruct;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));

        // Constant struct member access
        const SemaNodeView       nodeRightView = sema.viewSymbolList(node.nodeRightRef);
        const std::span<Symbol*> symbols       = nodeRightView.symList();
        const size_t             finalSymCount = symbols.size();
        if (nodeLeftView.cst() && finalSymCount == 1 && symbols[0]->isVariable())
        {
            const SymbolVariable& symVar = symbols[0]->cast<SymbolVariable>();
            SWC_RESULT(ConstantExtract::structMember(sema, *nodeLeftView.cst(), symVar, targetNodeRef, node.nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference() || sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (finalSymCount == 1 && symbols[0]->isVariable() && needsStructMemberRuntimeStorage(sema, node, nodeLeftView))
        {
            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(targetNodeRef);
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(targetNodeRef, payload);
            }

            if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
            {
                payload->runtimeStorageSym = boundStorage;
            }
            else
            {
                auto& storageSym = registerUniqueMemberRuntimeStorageSymbol(sema, node);
                storageSym.registerAttributes(sema);
                storageSym.setDeclared(sema.ctx());
                SWC_RESULT(Match::ghosting(sema, storageSym));
                SWC_RESULT(completeMemberRuntimeStorageSymbol(sema, storageSym, memberRuntimeStorageTypeRef(sema)));
                payload->runtimeStorageSym = &storageSym;
            }
        }

        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, const TypeInfo& typeInfo)
    {
        const auto& aggregate = typeInfo.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        size_t memberIndex = 0;
        if (!SemaMemberAccess::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_symbol, SourceCodeRef{node.srcViewRef(), tokNameRef});
            diag.addArgument(Diagnostic::ARG_SYM, idRef);
            diag.report(sema.ctx());
            return Result::SkipChildren;
        }

        const TypeRef memberTypeRef = types[memberIndex];
        sema.setType(targetNodeRef, memberTypeRef);
        sema.setType(node.nodeRightRef, memberTypeRef);
        sema.setIsValue(node);
        sema.setIsValue(node.nodeRightRef);
        if (sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (nodeLeftView.cst() && nodeLeftView.cst()->isAggregateStruct())
        {
            const auto& values = nodeLeftView.cst()->getAggregateStruct();
            SWC_ASSERT(memberIndex < values.size());
            sema.setConstant(targetNodeRef, values[memberIndex]);
        }
        return Result::SkipChildren;
    }
}

Result SemaMemberAccess::resolve(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet)
{
    SemaNodeView        nodeLeftView  = sema.viewNodeTypeConstantSymbol(node.nodeLeftRef);
    const SemaNodeView  nodeRightView = sema.viewNode(node.nodeRightRef);
    const TokenRef      tokNameRef    = nodeRightView.node()->tokRef();
    const IdentifierRef idRef         = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());
    SWC_ASSERT(nodeRightView.node()->is(AstNodeId::Identifier));

    // Namespace
    if (nodeLeftView.sym() && nodeLeftView.sym()->isNamespace())
        return memberNamespace(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    SWC_ASSERT(nodeLeftView.type());

    // Enum
    if (nodeLeftView.type()->isEnum())
        return memberEnum(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type()->isInterface())
        return memberInterface(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type()->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, *nodeLeftView.type());

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type();
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        SWC_RESULT(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));
        typeInfo = &sema.typeMgr().get(sema.typeMgr().structTypeInfo());
    }
    else if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TypeInfo, typeInfoRef, {node.srcViewRef(), tokNameRef}));
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer() || typeInfo->isReference())
    {
        typeInfo = &sema.typeMgr().get(typeInfo->payloadTypeRef());
    }

    // Struct
    if (typeInfo->isStruct())
        return memberStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Pointer/Reference
    if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference())
    {
        sema.setType(memberRef, nodeLeftView.type()->payloadTypeRef());
        sema.setIsValue(node);
        return Result::SkipChildren;
    }

    SWC_INTERNAL_ERROR();
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    // Parser tags the callee expression when building a call: `a.foo()`.
    const bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);
    return SemaMemberAccess::resolve(sema, sema.curNodeRef(), *this, allowOverloadSet);
}

SWC_END_NAMESPACE();
