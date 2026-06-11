#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef transparentCastExprOperandRef(const AstNode& node)
    {
        switch (node.id())
        {
            case AstNodeId::AutoCastExpr:
                return node.cast<AstAutoCastExpr>().nodeExprRef;
            case AstNodeId::CastExpr:
                return node.cast<AstCastExpr>().nodeExprRef;
            case AstNodeId::AsCastExpr:
                return node.cast<AstAsCastExpr>().nodeExprRef;
            default:
                return AstNodeRef::invalid();
        }
    }

    AstNodeRef transparentConditionExprOperandRef(const AstNode& node)
    {
        const AstNodeRef castOperandRef = transparentCastExprOperandRef(node);
        if (castOperandRef.isValid())
            return castOperandRef;

        switch (node.id())
        {
            case AstNodeId::ParenExpr:
                return node.cast<AstParenExpr>().nodeExprRef;
            default:
                return AstNodeRef::invalid();
        }
    }

    bool isNonReassignableNullableVariable(Sema& sema, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) && !symVar.hasExtraFlag(SymbolVariableFlagsE::Let))
            return false;
        if (!symVar.typeRef().isValid())
            return false;

        const TypeInfo& symType = sema.typeMgr().get(symVar.typeRef());
        if (symType.isReference())
            return false;

        TypeRef nullableTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), symVar.typeRef());
        if (nullableTypeRef.isInvalid())
            nullableTypeRef = symVar.typeRef();

        return sema.typeMgr().get(nullableTypeRef).isNullable();
    }
}

TypeRef SemaHelpers::unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef)
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

TypeRef SemaHelpers::ensureStructTypeRef(Sema& sema, SymbolStruct& symStruct)
{
    TypeRef typeRef = symStruct.typeRef();
    if (typeRef.isValid())
        return typeRef;

    typeRef = sema.typeMgr().addType(TypeInfo::makeStruct(&symStruct));
    symStruct.setTypeRef(typeRef);
    symStruct.setTyped(sema.ctx());
    return typeRef;
}

TypeRef SemaHelpers::unwrapAliasRefType(TaskContext& ctx, TypeRef typeRef)
{
    while (typeRef.isValid())
    {
        const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
        const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias);
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

SymbolFunction* SemaHelpers::callableTypeFunction(TaskContext& ctx, TypeRef typeRef)
{
    typeRef = unwrapLambdaBindingType(ctx, typeRef);
    if (!typeRef.isValid())
        return nullptr;

    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    if (!typeInfo.isFunction())
        return nullptr;

    return &typeInfo.payloadSymFunction();
}

const SymbolFunction* SemaHelpers::resolveLambdaBindingFunction(Sema& sema)
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

bool SemaHelpers::binaryOpNeedsOverflowSafety(TokenId canonicalOp, AstModifierFlags modifierFlags)
{
    switch (canonicalOp)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
        case TokenId::SymSlash:
        case TokenId::SymPercent:
            return !modifierFlags.has(AstModifierFlagsE::Wrap);

        case TokenId::SymLowerLower:
        case TokenId::SymGreaterGreater:
            return true;

        default:
            return false;
    }
}

bool SemaHelpers::canUseContextualBinding(Sema& sema, AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = sema.node(nodeRef);
    switch (node.id())
    {
        case AstNodeId::AutoMemberAccessExpr:
        case AstNodeId::IntegerLiteral:
        case AstNodeId::BinaryLiteral:
        case AstNodeId::HexaLiteral:
        case AstNodeId::FloatLiteral:
        case AstNodeId::NullLiteral:
        case AstNodeId::ArrayLiteral:
        case AstNodeId::StructLiteral:
            return true;

        case AstNodeId::BinaryExpr:
        {
            const auto& binary = node.cast<AstBinaryExpr>();
            return canUseContextualBinding(sema, binary.nodeLeftRef) || canUseContextualBinding(sema, binary.nodeRightRef);
        }

        case AstNodeId::ConditionalExpr:
        {
            const auto& conditional = node.cast<AstConditionalExpr>();
            return canUseContextualBinding(sema, conditional.nodeTrueRef) || canUseContextualBinding(sema, conditional.nodeFalseRef);
        }

        case AstNodeId::NullCoalescingExpr:
        {
            const auto& nullCoalescing = node.cast<AstNullCoalescingExpr>();
            return canUseContextualBinding(sema, nullCoalescing.nodeLeftRef) || canUseContextualBinding(sema, nullCoalescing.nodeRightRef);
        }

        case AstNodeId::ParenExpr:
            return canUseContextualBinding(sema, node.cast<AstParenExpr>().nodeExprRef);

        case AstNodeId::UnaryExpr:
            return canUseContextualBinding(sema, node.cast<AstUnaryExpr>().nodeExprRef);

        default:
            return false;
    }
}

bool SemaHelpers::isTransparentExprNode(const AstNode& node)
{
    return transparentConditionExprOperandRef(node).isValid();
}

AstNodeRef SemaHelpers::resolveTransparentExprSourceRef(Sema& sema, AstNodeRef nodeRef)
{
    AstNodeRef sourceRef = nodeRef;
    while (sourceRef.isValid())
    {
        const AstNodeRef nextRef = transparentCastExprOperandRef(sema.node(sourceRef));
        if (nextRef.isInvalid())
            return sourceRef;

        sourceRef = nextRef;
    }

    return AstNodeRef::invalid();
}

AstNodeRef SemaHelpers::resolveTransparentConditionExprSourceRef(Sema& sema, AstNodeRef nodeRef)
{
    AstNodeRef sourceRef = nodeRef;
    while (sourceRef.isValid())
    {
        const AstNodeRef nextRef = transparentConditionExprOperandRef(sema.node(sourceRef));
        if (nextRef.isInvalid())
            return sourceRef;

        sourceRef = nextRef;
    }

    return AstNodeRef::invalid();
}

SemaHelpers::NullableGuardInfo SemaHelpers::nullableGuardInfo(Sema& sema, AstNodeRef exprRef)
{
    NullableGuardInfo result;
    if (exprRef.isInvalid())
        return result;

    const AstNode& exprNode = sema.node(exprRef);
    if (exprNode.is(AstNodeId::UnaryExpr) && sema.token(exprNode.codeRef()).id == TokenId::SymBang)
    {
        const auto&       unary = exprNode.cast<AstUnaryExpr>();
        NullableGuardInfo child = nullableGuardInfo(sema, unary.nodeExprRef);
        child.nonNullWhenTrue   = !child.nonNullWhenTrue;
        return child;
    }

    const SemaNodeView view = sema.viewTypeSymbol(exprRef);
    if (!view.hasSymbol() || !view.sym() || !view.sym()->isVariable())
        return result;

    const auto& symVar = view.sym()->cast<SymbolVariable>();
    if (!isNonReassignableNullableVariable(sema, symVar))
        return result;

    result.symbol = view.sym();
    return result;
}

SWC_END_NAMESPACE();
