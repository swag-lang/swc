#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

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
}

Result AstParenExpr::semaPostNode(Sema& sema)
{
    sema.inheritSema(*this, nodeExprRef);
    return Result::Continue;
}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    if (sema.hasConstant(sema.curNodeRef()))
        return Result::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, srcViewRef(), tokRef());
    RESULT_VERIFY(ret);

    return checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols());
}

Result AstAutoMemberAccessExpr::semaPostNode(Sema& sema)
{
    const auto node = sema.node(sema.curNodeRef()).cast<AstAutoMemberAccessExpr>();

    // Parser tags the callee expression when building a call: `.foo()`.
    const bool allowOverloadSet = node->hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);

    const SymbolMap*      symMapHint = nullptr;
    const SymbolFunction* symFunc    = sema.frame().function();
    const SymbolVariable* symMe      = nullptr;

    if (symFunc && !symFunc->parameters().empty())
    {
        symMe = symFunc->parameters()[0];
        if (symMe->idRef() == sema.idMgr().nameMe())
        {
            const auto      typeRef  = symMe->typeRef();
            const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
            SWC_ASSERT(typeInfo.isReference());
            const TypeInfo& pointeeType = sema.typeMgr().get(typeInfo.underlyingTypeRef());
            if (pointeeType.isStruct())
                symMapHint = &pointeeType.symStruct();
            else if (pointeeType.isEnum())
                symMapHint = &pointeeType.symEnum();
        }
        else
        {
            symMe = nullptr;
        }
    }

    if (!symMapHint)
        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());

    const SemaNodeView  nodeRightView(sema, node->nodeIdentRef);
    const TokenRef      tokNameRef = nodeRightView.node->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), node->srcViewRef(), tokNameRef);

    MatchContext lookUpCxt;
    lookUpCxt.srcViewRef = node->srcViewRef();
    lookUpCxt.tokRef     = tokNameRef;
    lookUpCxt.symMapHint = symMapHint;

    RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

    // Bind the symbol list to the auto-member-access node (it gets substituted below).
    const Result amb = checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols());
    RESULT_VERIFY(amb);

    // Substitute with an AstMemberAccessExpr
    auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(node->tokRef());
    auto [meRef, mePtr]     = sema.ast().makeNode<AstNodeId::Identifier>(node->tokRef());
    sema.setSymbol(meRef, symMe);
    SemaInfo::setIsValue(*mePtr);

    nodePtr->nodeLeftRef  = meRef;
    nodePtr->nodeRightRef = node->nodeIdentRef;

    // Re-bind the resolved list to the substituted member-access node as well,
    // so downstream passes can read from the final node.
    sema.setSymbolList(nodeRef, sema.getSymbolList(sema.curNodeRef()));

    sema.semaInfo().setSubstitute(sema.curNodeRef(), nodeRef);
    SemaInfo::setIsValue(*nodePtr);

    return Result::Continue;
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    // Parser tags the callee expression when building a call: `a.foo()`.
    const bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);

    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);
    TokenRef           tokNameRef;

    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));
    tokNameRef = nodeRightView.node->tokRef();

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &namespaceSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind both the RHS identifier and the member-access expr to the (possibly filtered) candidates.
        // First bind for the member-access node (curNodeRef).
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        // Then bind the same final list to the RHS identifier node.
        // If you don't have a getter for the stored list, re-run filtering locally:
        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightView.nodeRef, callables);
            else
                sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }

        return Result::SkipChildren;
    }

    SWC_ASSERT(nodeLeftView.type);

    // Enum
    if (nodeLeftView.type->isEnum())
    {
        const SymbolEnum& enumSym = nodeLeftView.type->symEnum();
        if (!enumSym.isCompleted())
            return sema.waitCompleted(&enumSym, srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightView.nodeRef, callables);
            else
                sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }

        return Result::SkipChildren;
    }

    // Interface
    if (nodeLeftView.type->isInterface())
    {
        const SymbolInterface& symInterface = nodeLeftView.type->symInterface();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, srcViewRef(), tokNameRef);
        // TODO
        return Result::SkipChildren;
    }

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (typeInfoRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameTypeInfoStruct(), srcViewRef(), tokNameRef);
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer())
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());
    else if (typeInfo->isReference())
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());

    // Struct
    if (typeInfo->isStruct())
    {
        const SymbolStruct& symStruct = typeInfo->symStruct();
        if (!symStruct.isCompleted())
            return sema.waitCompleted(&symStruct, srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &symStruct;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightRef, callables);
            else
                sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        }

        // Constant struct member access
        const auto finalSymCount = sema.getSymbolList(nodeRightRef).size(); // if unavailable, see note below.
        if (nodeLeftView.cst && finalSymCount == 1 && sema.getSymbolList(nodeRightRef)[0]->isVariable())
        {
            const SymbolVariable& symVar = sema.getSymbolList(nodeRightRef)[0]->cast<SymbolVariable>();
            RESULT_VERIFY(SemaHelpers::extractConstantStructMember(sema, *nodeLeftView.cst, symVar, sema.curNodeRef(), nodeRightView.nodeRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference() || SemaInfo::isLValue(sema.node(nodeLeftRef)))
            SemaInfo::setIsLValue(*this);
        return Result::SkipChildren;
    }

    // Pointer/Reference
    if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference())
    {
        sema.setType(sema.curNodeRef(), nodeLeftView.type->typeRef());
        SemaInfo::setIsValue(*this);
        return Result::SkipChildren;
    }

    // TODO
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeInt(32, TypeInfo::Sign::Signed));
    SemaInfo::setIsValue(*this);
    return Result::SkipChildren;
}

Result AstIndexExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);
    const SemaNodeView nodeArgView(sema, nodeArgRef);

    if (!nodeArgView.type->isInt())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeArgRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (nodeExprView.type->isArray())
    {
        const auto& arrayDims   = nodeExprView.type->arrayDims();
        const auto  numExpected = arrayDims.size();

        if (numExpected > 1)
        {
            std::vector<uint64_t> dims;
            for (size_t i = 1; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type->arrayElemTypeRef(), nodeExprView.type->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type->arrayElemTypeRef());
        }

        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isBlockPointer())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->typeRef());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isSlice())
    {
        sema.setType(sema.curNodeRef(), nodeExprView.type->typeRef());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isString() || nodeExprView.type->isCString())
    {
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeU8());
        SemaInfo::setIsLValue(*this);
    }
    else if (nodeExprView.type->isValuePointer())
    {
        return SemaError::raisePointerArithmeticValuePointer(sema, sema.node(nodeExprRef), nodeExprRef, nodeExprView.typeRef);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

Result AstIndexListExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    // Array
    if (nodeExprView.type->isArray())
    {
        SmallVector<AstNodeRef> children;
        sema.ast().nodes(children, spanChildrenRef);

        const auto&    arrayDims   = nodeExprView.type->arrayDims();
        const uint64_t numExpected = arrayDims.size();
        const size_t   numGot      = children.size();

        if (numGot > numExpected)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[numExpected]);
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(numExpected));
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(numGot));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (numGot < numExpected)
        {
            std::vector<uint64_t> dims;
            for (size_t i = numGot; i < numExpected; i++)
                dims.push_back(arrayDims[i]);
            const auto typeArray = TypeInfo::makeArray(dims, nodeExprView.type->arrayElemTypeRef(), nodeExprView.type->flags());
            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(typeArray));
        }
        else
        {
            sema.setType(sema.curNodeRef(), nodeExprView.type->arrayElemTypeRef());
        }

        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }

    // Slice
    else if (nodeExprView.type->isSlice())
    {
        SmallVector<AstNodeRef> children;
        sema.ast().nodes(children, spanChildrenRef);

        const size_t numGot = children.size();
        if (numGot > 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_num_dims, children[1]);
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(1));
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(numGot));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        sema.setType(sema.curNodeRef(), nodeExprView.type->arrayElemTypeRef());
        if (SemaInfo::isLValue(sema.node(nodeExprRef)))
            SemaInfo::setIsLValue(*this);
    }
    else
    {
        return SemaError::raiseTypeNotIndexable(sema, nodeExprRef, nodeExprView.typeRef);
    }

    SemaInfo::setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
