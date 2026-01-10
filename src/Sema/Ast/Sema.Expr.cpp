#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return Result::Continue;
}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    if (sema.hasConstant(sema.curNodeRef()))
        return Result::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const Result ret = SemaMatch::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && flags().has(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, srcViewRef(), tokRef());
    RESULT_VERIFY(ret);

    sema.setSymbol(sema.curNodeRef(), lookUpCxt.first());
    return Result::Continue;
}

Result AstAutoScopedIdentifier::semaPostNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
    return Result::SkipChildren;
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);
    TokenRef           tokNameRef;

    if (nodeRightView.node->is(AstNodeId::Identifier))
        tokNameRef = nodeRightView.node->tokRef();
    else
        SWC_UNREACHABLE();

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &namespaceSym;

        RESULT_VERIFY(SemaMatch::match(sema, lookUpCxt, idRef));

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return Result::SkipChildren;
    }

    if (!nodeLeftView.type)
        return SemaError::raiseInternal(sema, *this);

    // Enum
    if (nodeLeftView.type->isEnum())
    {
        const SymbolEnum& enumSym = nodeLeftView.type->enumSym();
        if (!enumSym.isCompleted())
            return sema.waitCompleted(&enumSym, srcViewRef(), tokNameRef);

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        RESULT_VERIFY(SemaMatch::match(sema, lookUpCxt, idRef));

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return Result::SkipChildren;
    }

    // Interface
    if (nodeLeftView.type->isInterface())
    {
        const SymbolInterface& symInterface = nodeLeftView.type->interfaceSym();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, srcViewRef(), tokNameRef);
        // TODO
        return Result::SkipChildren;
    }

    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo && typeInfo->isPointer())
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());

    // Struct
    if (typeInfo->isStruct())
    {
        const SymbolStruct& symStruct = typeInfo->structSym();
        if (!symStruct.isCompleted())
            return sema.waitCompleted(&symStruct, srcViewRef(), tokNameRef);

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &symStruct;

        RESULT_VERIFY(SemaMatch::match(sema, lookUpCxt, idRef));

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        if (nodeLeftView.type->isPointer() || SemaInfo::isLValue(sema.node(nodeLeftRef)))
            SemaInfo::setIsLValue(*this);
        return Result::SkipChildren;
    }

    // TODO
    if (nodeLeftView.type->isPointer())
        sema.setType(sema.curNodeRef(), nodeLeftView.type->typeRef());
    else
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
        return Result::Stop;
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
        return SemaError::raisePointerArithmetic(sema, sema.node(nodeExprRef), nodeExprRef, nodeExprView.typeRef);
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
            return Result::Stop;
        }

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Stop;
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
            return Result::Stop;
        }

        for (const AstNodeRef nodeRef : children)
        {
            const SemaNodeView nodeArgView(sema, nodeRef);
            if (!nodeArgView.type->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeArgView.typeRef);
                diag.report(sema.ctx());
                return Result::Stop;
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
