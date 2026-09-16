#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
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

Result AstCastExpr::semaPostNode(Sema& sema)
{
    if (!hasFlag(AstCastExprFlagsE::Explicit))
        return Result::Continue;

    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView srcTypeView  = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    if (nodeTypeView.type() && nodeTypeView.type()->isBool() && !modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}))
        SWC_RESULT(SemaCheck::typePattern(sema, nodeExprRef));

    // Value-check
    if (!modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}))
        SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst | AstModifierFlagsE::Wrap | AstModifierFlagsE::Try | AstModifierFlagsE::Assume));

    // Cast kind
    CastFlags castFlags = CastFlagsE::Zero;
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);
    if (modifierFlags.has(AstModifierFlagsE::Wrap))
        castFlags.add(CastFlagsE::NoOverflow);
    if (modifierFlags.has(AstModifierFlagsE::Try))
        castFlags.add(CastFlagsE::Try);
    if (modifierFlags.has(AstModifierFlagsE::Assume))
        castFlags.add(CastFlagsE::Assume);
    castFlags.add(CastFlagsE::FromExplicitNode);

    const bool runtimeTarget     = sema.isValue(nodeTypeRef) && SemaHelpers::isTypeLikeTypeRef(sema.ctx(), nodeTypeView.typeRef());
    const bool runtimeTypeSource = modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}) &&
                                   sema.isValue(nodeExprRef) && SemaHelpers::isTypeLikeTypeRef(sema.ctx(), srcTypeView.typeRef()) &&
                                   !sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), nodeTypeView.typeRef()) && !nodeTypeView.type()->isTypeInfo();
    if (runtimeTarget || runtimeTypeSource)
    {
        const bool tryCast    = modifierFlags.has(AstModifierFlagsE::Try);
        const bool assumeCast = modifierFlags.has(AstModifierFlagsE::Assume);
        if (tryCast == assumeCast || modifierFlags.hasAny({AstModifierFlagsE::Bit, AstModifierFlagsE::Wrap, AstModifierFlagsE::UnConst}))
            return SemaError::raise(sema, DiagnosticId::sema_err_dynamic_cast_modifier, sema.curNodeRef());

        SemaNodeView targetView = sema.viewNodeTypeConstant(nodeTypeRef);
        SemaHelpers::normalizeTypeOperandToConstant(sema, targetView);
        const TypeRef nullableTypeInfo = sema.typeMgr().addType(TypeInfo::makeTypeInfo(TypeInfoFlagsE::Nullable));
        SWC_RESULT(Cast::cast(sema, targetView, nullableTypeInfo, CastKind::Implicit));

        SemaNodeView  sourceView  = sema.viewNodeTypeConstant(nodeExprRef);
        const bool    typeQuery   = !sema.isValue(nodeExprRef) || SemaHelpers::isTypeLikeTypeRef(sema.ctx(), sourceView.typeRef());
        const TypeRef knownTarget = SemaHelpers::resolveRepresentedTypeRef(sema, targetView);
        const TypeRef knownSource = SemaHelpers::resolveRepresentedTypeRef(sema, sourceView);
        if (typeQuery && knownTarget.isValid() && (knownSource.isValid() || !sema.isValue(nodeExprRef)) &&
            !sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), knownTarget))
        {
            sema.inheritPayloadFlags(*this, nodeExprRef);
            sema.setType(sema.curNodeRef(), sourceView.typeRef());
            SemaNodeView view = sema.curViewNodeTypeConstant();
            return Cast::castDynamic(sema, view, knownTarget, castFlags);
        }
        TypeInfoFlags resultFlags = tryCast ? TypeInfoFlagsE::Nullable : TypeInfoFlagsE::Zero;
        if (!typeQuery && sourceView.type()->isConst())
            resultFlags.add(TypeInfoFlagsE::Const);
        const TypeRef resultType = sema.typeMgr().addType(typeQuery ? TypeInfo::makeTypeInfo(resultFlags) : TypeInfo::makeAny(resultFlags));
        if (typeQuery)
        {
            SemaHelpers::normalizeTypeOperandToConstant(sema, sourceView);
            SWC_RESULT(Cast::cast(sema, sourceView, nullableTypeInfo, CastKind::Implicit));
        }
        else
        {
            TypeInfoFlags sourceFlags = resultFlags;
            sourceFlags.add(TypeInfoFlagsE::Nullable);
            SWC_RESULT(Cast::cast(sema, sourceView, sema.typeMgr().addType(TypeInfo::makeAny(sourceFlags)), CastKind::Implicit));
            const uint64_t count       = 4;
            const TypeRef  storageType = sema.typeMgr().addType(TypeInfo::makeArray(std::span{&count, 1}, sema.typeMgr().typeU64()));
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), *this, storageType, "__runtime_cast_storage"));
        }
        sema.clearConstant(sema.curNodeRef());
        sema.setType(sema.curNodeRef(), resultType);
        sema.setIsValue(*this);
        auto& payload              = SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef());
        payload.runtimeTypeCast    = typeQuery;
        payload.runtimeValueCast   = !typeQuery;
        payload.assumedDynamicCast = assumeCast;
        if (assumeCast)
            SWC_RESULT(SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::DynCast, codeRef()));
        const auto function = typeQuery ? IdentifierManager::RuntimeFunctionKind::RuntimeTypeCast : IdentifierManager::RuntimeFunctionKind::RuntimeValueCast;
        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), function, codeRef());
    }

    sema.inheritPayloadFlags(*this, nodeExprView.nodeRef());
    if (srcTypeView.hasConstant())
        sema.setConstant(sema.curNodeRef(), srcTypeView.cstRef());
    else
        sema.setType(sema.curNodeRef(), srcTypeView.typeRef());
    if (sema.isFoldedTypedConst(nodeExprRef))
        sema.setFoldedTypedConst(sema.curNodeRef());

    SemaNodeView view = sema.curViewNodeTypeConstant();
    // The generated outer cast of 'is' tests presence, including a runtime target's any?.
    const CastKind castKind = nodeTypeView.type()->isBool() && sema.token(codeRef()).id == TokenId::KwdIs ? CastKind::BoolExpr : CastKind::Explicit;
    SWC_RESULT(Cast::cast(sema, view, nodeTypeView.typeRef(), castKind, castFlags));
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
    const SemaNodeView source            = sema.viewType(nodeExprRef);
    const SemaNodeView target            = sema.viewType(nodeTypeRef);
    const TypeRef      targetRef         = sema.typeMgr().unwrapAlias(sema.ctx(), target.typeRef());
    const TypeInfo&    targetType        = sema.typeMgr().get(targetRef);
    const TypeRef      borrowedTargetRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(target.typeRef(), TypeInfoFlagsE::Const));
    const bool         typeQuery         = !sema.isValue(nodeExprRef) ||
                           (SemaHelpers::isTypeLikeTypeRef(sema.ctx(), source.typeRef()) && !sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), borrowedTargetRef));

    // A pattern names the object type. Reuse the explicit dynamic cast after deriving
    // its borrowed destination, so checks, pointer adjustment, and lifetime rules agree.
    AstNodeRef castTypeRef = nodeTypeRef;
    if (!typeQuery && !sema.isValue(nodeTypeRef))
    {
        DynamicStructCastSourceInfo sourceInfo;
        if (!resolveDynamicStructCastSourceInfo(sema, nodeExprRef, source.typeRef(), sourceInfo))
            return SemaError::raiseCannotCast(sema, nodeExprRef, source.typeRef(), target.typeRef());
        TypeInfoFlags flags       = sourceInfo.sourceIsConst ? TypeInfoFlagsE::Const : TypeInfoFlagsE::Zero;
        TypeInfo      destination = targetType.isInterface() ? targetType : TypeInfo::makeValuePointer(target.typeRef(), flags);
        if (sourceInfo.sourceIsConst)
            destination.addFlag(TypeInfoFlagsE::Const);
        auto [typeRef, typeNode] = sema.ast().makeNode<AstNodeId::Identifier>(sema.node(nodeTypeRef).tokRef());
        typeNode->addFlag(AstIdentifierFlagsE::GenericTypeBinding);
        sema.setType(typeRef, sema.typeMgr().addType(destination));
        castTypeRef = typeRef;
    }

    auto [castRef, castNode] = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
    castNode->addFlag(AstCastExprFlagsE::Explicit);
    castNode->modifierFlags = AstModifierFlagsE::Try;
    castNode->nodeExprRef   = nodeExprRef;
    castNode->nodeTypeRef   = castTypeRef;
    AstNodeRef resultRef    = castRef;
    if (!hasFlag(AstIsTypeExprFlagsE::Binding))
    {
        auto [boolRef, boolNode] = sema.ast().makeNode<AstNodeId::BuiltinType>(tokRef());
        boolNode->typeTokenId    = TokenId::TypeBool;
        auto [testRef, testNode] = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
        testNode->addFlag(AstCastExprFlagsE::Explicit);
        testNode->nodeTypeRef = boolRef;
        testNode->nodeExprRef = castRef;
        resultRef             = testRef;
    }
    sema.setSubstitute(sema.curNodeRef(), resultRef);
    sema.restartCurrentNode(resultRef);
    return Result::Continue;
}

Result AstAutoCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprView     = sema.viewTypeConstant(nodeExprRef);

    // Value-check
    if (!modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}))
        SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst | AstModifierFlagsE::Wrap | AstModifierFlagsE::Try | AstModifierFlagsE::Assume));

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
