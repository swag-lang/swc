#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef castRuntimeStorageTypeRef(Sema& sema, const SemaNodeView& srcView, const SemaNodeView& dstView)
    {
        if (!srcView.type() || !dstView.type())
            return TypeRef::invalid();
        if (srcView.hasConstant())
            return TypeRef::invalid();
        return Cast::runtimeStorageTypeRef(sema, srcView.typeRef(), dstView.typeRef(), ConstantRef::invalid());
    }

}

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
    // @MinusLiteralSuffix
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

    const SemaNodeView dstTypeView = sema.curViewType();
    SWC_RESULT(Cast::retargetLiteralRuntimeStorageIfNeeded(sema, nodeExprView.nodeRef(), srcTypeView.typeRef(), dstTypeView.typeRef()));
    const TypeRef runtimeStorageTypeRef = castRuntimeStorageTypeRef(sema, srcTypeView, dstTypeView);
    if (runtimeStorageTypeRef.isValid() && sema.isCurrentFunction())
    {
        auto& storageSym = SemaHelpers::getOrCreateRuntimeStorageSymbol(sema, sema.curNodeRef(), *this, "__cast_runtime_storage");
        SWC_RESULT(SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, runtimeStorageTypeRef));
    }

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

    return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::As, codeRef());
}

Result AstIsTypeExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprTypeView = sema.viewType(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    DynamicStructCastSourceInfo castInfo;
    if (!resolveDynamicStructCastSourceInfo(sema, nodeExprView.nodeRef(), exprTypeView.typeRef(), castInfo))
        return SemaError::raiseCannotCast(sema, sema.curNodeRef(), exprTypeView.typeRef(), nodeTypeView.typeRef());

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
    sema.setIsValue(*this);

    return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::Is, codeRef());
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
