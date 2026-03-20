#include "pch.h"
#include "Compiler/Sema/Ast/Sema.MemberAccess.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
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
    bool parsePositionalMemberIndex(std::string_view name, size_t& outIndex)
    {
        if (!name.starts_with("item"))
            return false;
        if (name.size() <= 4)
            return false;

        size_t value = 0;
        for (const char c : name.substr(4))
        {
            if (c < '0' || c > '9')
                return false;
            value = value * 10 + static_cast<size_t>(c - '0');
        }

        outIndex = value;
        return true;
    }

    bool lookupStructPositionalAlias(Sema& sema, const SymbolStruct& symStruct, IdentifierRef idRef, SmallVector<const Symbol*>& outSymbols)
    {
        size_t positionalIndex = 0;
        if (!parsePositionalMemberIndex(sema.idMgr().get(idRef).name, positionalIndex))
            return false;

        const auto& fields = symStruct.fields();
        if (positionalIndex >= fields.size() || !fields[positionalIndex])
            return false;

        outSymbols.clear();
        outSymbols.push_back(fields[positionalIndex]);
        return true;
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

    Result bindMemberSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSet, std::span<const Symbol*> symbols)
    {
        SmallVector<const Symbol*> filteredSymbols;
        removeEmptyFunctionDeclarations(symbols, filteredSymbols);
        SmallVector<const Symbol*> runtimeSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeRef, filteredSymbols.span(), runtimeSymbols));

        if (runtimeSymbols.size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRef, runtimeSymbols);
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(runtimeSymbols, callables))
                sema.setSymbolList(nodeRef, callables);
            else
                sema.setSymbolList(nodeRef, runtimeSymbols);
        }

        return Result::Continue;
    }

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

namespace
{
    Result memberNamespace(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym()->cast<SymbolNamespace>();

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &namespaceSym;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        SWC_RESULT(checkAmbiguityAndBindSymbols(sema, targetNodeRef, allowOverloadSet, lookUpCxt.symbols()));
        SWC_RESULT(bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols()));

        return Result::SkipChildren;
    }

    Result memberEnum(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum& enumSym = nodeLeftView.type()->payloadSymEnum();
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &enumSym;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SWC_RESULT(checkAmbiguityAndBindSymbols(sema, targetNodeRef, allowOverloadSet, lookUpCxt.symbols()));
        SWC_RESULT(bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols()));

        return Result::SkipChildren;
    }

    Result memberInterface(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type()->payloadSymInterface();
        SWC_RESULT(sema.waitSemaCompleted(&symInterface, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef = SourceCodeRef{node->srcViewRef(), tokNameRef};

        if (nodeLeftView.sym() && nodeLeftView.sym()->isImpl())
            lookUpCxt.symMapHint = nodeLeftView.sym()->asSymMap();
        else
            lookUpCxt.symMapHint = &symInterface;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SWC_RESULT(checkAmbiguityAndBindSymbols(sema, targetNodeRef, allowOverloadSet, lookUpCxt.symbols()));
        SWC_RESULT(bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols()));

        return Result::SkipChildren;
    }

    Result memberStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo* typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo->payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&symStruct, {node->srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node->srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symStruct;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SmallVector<const Symbol*> aliasSymbols;
        std::span<const Symbol*>   matchedSymbols = lookUpCxt.symbols();
        if (matchedSymbols.empty() && lookupStructPositionalAlias(sema, symStruct, idRef, aliasSymbols))
            matchedSymbols = aliasSymbols;

        // Bind member-access node (curNodeRef) and RHS identifier.
        SWC_RESULT(checkAmbiguityAndBindSymbols(sema, targetNodeRef, allowOverloadSet, matchedSymbols));
        SWC_RESULT(bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, matchedSymbols));

        // Constant struct member access
        const SemaNodeView       nodeRightView = sema.viewSymbolList(node->nodeRightRef);
        const std::span<Symbol*> symbols       = nodeRightView.symList();
        const size_t             finalSymCount = symbols.size();
        if (nodeLeftView.cst() && finalSymCount == 1 && symbols[0]->isVariable())
        {
            const SymbolVariable& symVar = symbols[0]->cast<SymbolVariable>();
            SWC_RESULT(ConstantExtract::structMember(sema, *nodeLeftView.cst(), symVar, targetNodeRef, node->nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference() || sema.isLValue(node->nodeLeftRef))
            sema.setIsLValue(*node);

        if (finalSymCount == 1 && symbols[0]->isVariable() && needsStructMemberRuntimeStorage(sema, *node, nodeLeftView))
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
                auto& storageSym = registerUniqueMemberRuntimeStorageSymbol(sema, *node);
                storageSym.registerAttributes(sema);
                storageSym.setDeclared(sema.ctx());
                SWC_RESULT(Match::ghosting(sema, storageSym));
                SWC_RESULT(completeMemberRuntimeStorageSymbol(sema, storageSym, memberRuntimeStorageTypeRef(sema)));
                payload->runtimeStorageSym = &storageSym;
            }
        }

        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, const TypeInfo* typeInfo)
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
            if (names[i].isValid() && names[i] == idRef)
            {
                memberIndex = i;
                found       = true;
                break;
            }

            if (idName == ("item" + std::to_string(i)))
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
        sema.setType(targetNodeRef, memberTypeRef);
        sema.setType(node->nodeRightRef, memberTypeRef);
        sema.setIsValue(*node);
        sema.setIsValue(node->nodeRightRef);
        if (sema.isLValue(node->nodeLeftRef))
            sema.setIsLValue(*node);

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
        return memberNamespace(sema, memberRef, &node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    SWC_ASSERT(nodeLeftView.type());

    // Enum
    if (nodeLeftView.type()->isEnum())
        return memberEnum(sema, memberRef, &node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type()->isInterface())
        return memberInterface(sema, memberRef, &node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type()->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, &node, nodeLeftView, idRef, tokNameRef, nodeLeftView.type());

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
        return memberStruct(sema, memberRef, &node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, typeInfo);

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
