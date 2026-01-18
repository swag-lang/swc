#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Match/Match.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

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

    MatchContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, srcViewRef(), tokRef());
    RESULT_VERIFY(ret);

    sema.setSymbolList(sema.curNodeRef(), lookUpCxt.symbols());
    return Result::Continue;
}

Result AstAutoMemberAccessExpr::semaPostNode(Sema& sema)
{
    const auto node = sema.node(sema.curNodeRef()).cast<AstAutoMemberAccessExpr>();

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
            if (typeInfo.isAnyPointer())
            {
                const TypeInfo& pointeeType = sema.typeMgr().get(typeInfo.underlyingTypeRef());
                if (pointeeType.isStruct())
                    symMapHint = &pointeeType.symStruct();
                else if (pointeeType.isEnum())
                    symMapHint = &pointeeType.symEnum();
            }
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

    // Substitute with an AstMemberAccessExpr
    auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(node->tokRef());
    auto [meRef, mePtr]     = sema.ast().makeNode<AstNodeId::Identifier>(node->tokRef());
    sema.setSymbol(meRef, symMe);
    SemaInfo::setIsValue(*mePtr);

    nodePtr->nodeLeftRef  = meRef;
    nodePtr->nodeRightRef = node->nodeIdentRef;

    sema.setSymbolList(nodeRef, lookUpCxt.symbols());
    sema.semaInfo().setSubstitute(sema.curNodeRef(), nodeRef);
    SemaInfo::setIsValue(*nodePtr);

    return Result::Continue;
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

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

        sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        sema.setSymbolList(sema.curNodeRef(), lookUpCxt.symbols());
        return Result::SkipChildren;
    }

    if (!nodeLeftView.type)
        return SemaError::raiseInternal(sema, *this);

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

        sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        sema.setSymbolList(sema.curNodeRef(), lookUpCxt.symbols());
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

    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo && typeInfo->isAnyPointer())
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

        sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        sema.setSymbolList(sema.curNodeRef(), lookUpCxt.symbols());

        // Constant struct member access
        if (nodeLeftView.cst && lookUpCxt.symbols().size() == 1 && lookUpCxt.symbols()[0]->isVariable())
        {
            const SymbolVariable&  symVar = lookUpCxt.symbols()[0]->cast<SymbolVariable>();
            const ConstantValue&   cst    = *nodeLeftView.cst;
            const std::string_view bytes  = cst.getStruct();

            const TypeInfo& typeField = symVar.typeInfo(sema.ctx());
            if (symVar.offset() + typeField.sizeOf(sema.ctx()) <= bytes.size())
            {
                const auto    fieldBytes = std::string_view(bytes.data() + symVar.offset(), typeField.sizeOf(sema.ctx()));
                ConstantValue cv;
                if (typeField.isStruct())
                {
                    cv = ConstantValue::makeStruct(sema.ctx(), typeField.typeRef(), fieldBytes);
                }
                else if (typeField.isBool())
                {
                    cv = ConstantValue::makeBool(sema.ctx(), *reinterpret_cast<const bool*>(fieldBytes.data()));
                }
                else if (typeField.isInt() || typeField.isChar() || typeField.isRune())
                {
                    uint64_t val = 0;
                    memcpy(&val, fieldBytes.data(), std::min((size_t) fieldBytes.size(), sizeof(val)));
                    const auto apsInt = ApsInt(val, typeField.intLikeBits(), typeField.isIntUnsigned());
                    cv                = ConstantValue::makeFromIntLike(sema.ctx(), apsInt, typeField);
                }
                else if (typeField.isFloat())
                {
                    ApFloat apFloat;
                    if (typeField.floatBits() == 32)
                        apFloat.set(*reinterpret_cast<const float*>(fieldBytes.data()));
                    else
                        apFloat.set(*reinterpret_cast<const double*>(fieldBytes.data()));
                    cv = ConstantValue::makeFloat(sema.ctx(), apFloat, typeField.floatBits());
                }

                if (cv.kind() != ConstantKind::Invalid)
                {
                    const auto cstRef = sema.cstMgr().addConstant(sema.ctx(), cv);
                    sema.setConstant(sema.curNodeRef(), cstRef);
                }
            }
        }

        if (nodeLeftView.type->isAnyPointer() || SemaInfo::isLValue(sema.node(nodeLeftRef)))
            SemaInfo::setIsLValue(*this);
        return Result::SkipChildren;
    }

    // Pointer
    if (nodeLeftView.type->isAnyPointer())
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
