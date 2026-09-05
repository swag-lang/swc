#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

Result AstAsCastExpr::semaPreNodeChild(const Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && sema.semaPayload<DynamicStructSwitchAsCastPayload>(sema.curNodeRef()))
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstSuffixLiteral::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeSuffixRef && sema.node(childRef).is(AstNodeId::Identifier))
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    const TaskContext& ctx             = sema.ctx();
    SemaNodeView       nodeLiteralView = sema.viewNodeTypeConstant(nodeLiteralRef);
    SWC_ASSERT(nodeLiteralView.cstRef().isValid());

    ConstantRef cstRef = nodeLiteralView.cstRef();

    // Special case for negation: we need to negate before casting, in order for -128's8 to compile, for example.
    // Swag.minusLiteralSuffix
    const auto* parentNode = sema.visit().parentNode();
    if (parentNode->is(AstNodeId::UnaryExpr))
    {
        const Token& tok = sema.token(parentNode->codeRef());
        if (tok.is(TokenId::SymMinus))
        {
            const ConstantValue& cst  = sema.cstMgr().get(cstRef);
            const TypeInfo&      type = sema.typeMgr().get(cst.typeRef());
            if (type.isInt())
            {
                ApsInt cpy = cst.getInt();

                bool overflow = false;
                cpy.negate(overflow);
                if (overflow)
                    return SemaError::raiseLiteralOverflow(sema, nodeLiteralRef, cst, cst.typeRef());
                cpy.setUnsigned(false);
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cst.type(ctx).payloadIntBits(), TypeInfo::Sign::Signed));
            }
            else if (type.isFloat())
            {
                ApFloat cpy = cst.getFloat();
                cpy.negate();
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpy, cst.type(ctx).payloadFloatBits()));
            }
        }
    }

    UserDefinedLiteralSuffixInfo suffixInfo;
    if (Cast::resolveUserDefinedLiteralSuffix(sema, sema.curNodeRef(), suffixInfo))
    {
        sema.setType(sema.curNodeRef(), nodeLiteralView.typeRef());
        sema.setIsValue(sema.curNodeRef());
        sema.setConstant(nodeLiteralView.nodeRef(), cstRef);
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    const SemaNodeView suffixView = sema.viewType(nodeSuffixRef);
    const TypeRef      typeRef    = suffixView.typeRef();
    sema.setType(sema.curNodeRef(), typeRef);
    sema.setIsValue(sema.curNodeRef());
    sema.setConstant(nodeLiteralView.nodeRef(), cstRef);
    nodeLiteralView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    SWC_RESULT(Cast::cast(sema, nodeLiteralView, typeRef, CastKind::LiteralSuffix));
    sema.setConstant(sema.curNodeRef(), nodeLiteralView.cstRef());

    return Result::Continue;
}

namespace
{
    // 'expr[as T]' reinterprets the pointed storage as a T and opens it: the result is
    // an lvalue place of T. Write protection through a const source follows the same
    // source-inspection route as the plain dereference.
    Result semaDerefPlace(Sema& sema, AstCastExpr& node)
    {
        const SemaNodeView exprView = sema.viewNodeTypeConstantSymbol(node.nodeExprRef);
        const SemaNodeView typeView = sema.viewType(node.nodeTypeRef);

        SWC_RESULT(SemaCheck::isValue(sema, exprView.nodeRef()));
        SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));

        const TypeRef   srcResolvedTypeRef = sema.typeMgr().unwrapAliasEnumOrSelf(sema.ctx(), exprView.typeRef());
        const TypeInfo& srcType            = sema.typeMgr().get(srcResolvedTypeRef.isValid() ? srcResolvedTypeRef : exprView.typeRef());
        if (!srcType.isAnyPointer())
            return SemaError::raiseDerefOperandType(sema, sema.curNodeRef(), exprView.nodeRef(), exprView.typeRef());

        // Use-site nullability: narrowing was already applied to the live view, so a
        // remaining 'nullable' means no dominating test proves this dereference safe.
        if (srcType.isNullable() && (!exprView.hasConstant() || exprView.cst()->isNull()) && !SemaHelpers::nullabilityValidatedBeforeInlining(sema))
            return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_nullable_deref, exprView.nodeRef(), exprView.typeRef());

        const TypeRef resultTypeRef = typeView.typeRef();
        SWC_RESULT(sema.waitSemaCompleted(&sema.typeMgr().get(resultTypeRef), node.nodeTypeRef));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        sema.setIsValue(node);
        sema.setIsLValue(node);
        return Result::Continue;
    }
}

Result AstCastExpr::semaPostNode(Sema& sema)
{
    if (hasFlag(AstCastExprFlagsE::DerefPlace))
        return semaDerefPlace(sema, *this);

    if (!hasFlag(AstCastExprFlagsE::Explicit))
        return Result::Continue;

    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView srcTypeView  = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst | AstModifierFlagsE::Wrap));

    // Cast kind
    CastFlags castFlags = CastFlagsE::Zero;
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);
    if (modifierFlags.has(AstModifierFlagsE::Wrap))
        castFlags.add(CastFlagsE::NoOverflow);
    castFlags.add(CastFlagsE::FromExplicitNode);

    sema.inheritPayloadFlags(*this, nodeExprView.nodeRef());
    if (srcTypeView.hasConstant())
        sema.setConstant(sema.curNodeRef(), srcTypeView.cstRef());
    else
        sema.setType(sema.curNodeRef(), srcTypeView.typeRef());
    if (sema.isFoldedTypedConst(nodeExprRef))
        sema.setFoldedTypedConst(sema.curNodeRef());

    SemaNodeView view = sema.curViewNodeTypeConstant();
    SWC_RESULT(Cast::cast(sema, view, nodeTypeView.typeRef(), CastKind::Explicit, castFlags));
    sema.setIsValue(*this);

    const SemaNodeView dstView                     = sema.curViewNodeTypeConstant();
    const bool         createLiteralRuntimeStorage = srcTypeView.hasConstant() && !dstView.hasConstant();
    SWC_RESULT(Cast::retargetLiteralRuntimeStorageIfNeeded(sema, nodeExprView.nodeRef(), srcTypeView.typeRef(), dstView.typeRef(), createLiteralRuntimeStorage));
    SWC_RESULT(Cast::attachCastRuntimeStorageIfNeeded(sema, sema.curNodeRef(), srcTypeView.typeRef(), dstView.typeRef(), srcTypeView.cstRef()));

    return Result::Continue;
}

Result AstAsCastExpr::semaPostNode(Sema& sema)
{
    if (sema.semaPayload<DynamicStructSwitchAsCastPayload>(sema.curNodeRef()))
    {
        sema.inheritPayload(*this, nodeExprRef);
        return Result::Continue;
    }

    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprTypeView = sema.viewType(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    const TypeRef targetTypeRef = sema.typeMgr().unwrapAlias(sema.ctx(), nodeTypeView.typeRef());
    if (sema.typeMgr().get(targetTypeRef).isInterface())
    {
        // Share the cast node itself so conversions, borrowing, and lowering stay identical.
        auto [castRef, castNode] = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
        castNode->setCodeRef(codeRef());
        castNode->addFlag(AstCastExprFlagsE::Explicit);
        castNode->nodeExprRef = nodeExprRef;
        castNode->nodeTypeRef = nodeTypeRef;
        sema.setSubstitute(sema.curNodeRef(), castRef);
        sema.restartCurrentNode(castRef);
        return Result::Continue;
    }

    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    DynamicStructCastSourceInfo castInfo;
    if (!resolveDynamicStructCastSourceInfo(sema, nodeExprView.nodeRef(), exprTypeView.typeRef(), castInfo))
        return SemaError::raiseCannotCast(sema, sema.curNodeRef(), exprTypeView.typeRef(), nodeTypeView.typeRef());

    TypeInfoFlags resultFlags = TypeInfoFlagsE::Nullable;
    if (castInfo.sourceIsConst || nodeTypeView.type()->isConst())
        resultFlags.add(TypeInfoFlagsE::Const);

    const TypeRef resultTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(nodeTypeView.typeRef(), resultFlags));
    sema.setType(sema.curNodeRef(), resultTypeRef);
    sema.setIsValue(*this);

    return SemaHelpers::attachRuntimeAsFunctionToNode(sema, sema.curNodeRef(), codeRef());
}

Result AstIsTypeExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprTypeView = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    TypeRef representedTypeRef = TypeRef::invalid();
    if (!sema.isValue(nodeExprView.nodeRef()))
        representedTypeRef = exprTypeView.typeRef();
    else if (SemaHelpers::isTypeLikeTypeRef(sema.ctx(), exprTypeView.typeRef()))
        representedTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, exprTypeView);

    if (representedTypeRef.isValid())
    {
        const TypeRef   interfaceTypeRef = sema.typeMgr().unwrapAlias(sema.ctx(), nodeTypeView.typeRef());
        const TypeInfo& interfaceType    = sema.typeMgr().get(interfaceTypeRef);
        if (!interfaceType.isInterface())
            return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_type_is_needs_interface, nodeTypeRef, interfaceTypeRef);

        const TypeRef   sourceTypeRef = sema.typeMgr().unwrapAlias(sema.ctx(), representedTypeRef);
        const TypeInfo& sourceType    = sema.typeMgr().get(sourceTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&sourceType, nodeExprRef));
        SWC_RESULT(sema.waitSemaCompleted(&interfaceType, nodeTypeRef));
        bool satisfies = false;
        if (sourceType.isStruct())
            satisfies = sourceType.payloadSymStruct().implementsInterfaceOrUsingFields(sema, interfaceType.payloadSymInterface());
        else if (sourceType.isInterface())
            satisfies = &sourceType.payloadSymInterface() == &interfaceType.payloadSymInterface();

        sema.setConstant(sema.curNodeRef(), satisfies ? sema.cstMgr().cstTrue() : sema.cstMgr().cstFalse());
        sema.setIsValue(*this);
        return Result::Continue;
    }

    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    DynamicStructCastSourceInfo castInfo;
    if (!resolveDynamicStructCastSourceInfo(sema, nodeExprView.nodeRef(), exprTypeView.typeRef(), castInfo))
        return SemaError::raiseCannotCast(sema, sema.curNodeRef(), exprTypeView.typeRef(), nodeTypeView.typeRef());

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
    sema.setIsValue(*this);

    return SemaHelpers::attachRuntimeIsFunctionToNode(sema, sema.curNodeRef(), codeRef());
}

Result AstAutoCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprView     = sema.viewTypeConstant(nodeExprRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst | AstModifierFlagsE::Wrap));

    // We do not know the destination type here (it comes from context),
    // but we still need the source expression type or constant. Copying the raw payload would
    // keep a call's callee symbol payload and expose `func()->T` instead of the call result `T`.
    if (exprView.hasConstant())
        sema.setConstant(sema.curNodeRef(), exprView.cstRef());
    else
        sema.setType(sema.curNodeRef(), exprView.typeRef());

    if (sema.isFoldedTypedConst(nodeExprRef))
        sema.setFoldedTypedConst(sema.curNodeRef());

    sema.setIsValue(*this);

    return Result::Continue;
}

SWC_END_NAMESPACE();
