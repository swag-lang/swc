#include "pch.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result SemaCheck::modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed)
{
    // Compute unsupported = mods & ~allowed
    const AstModifierFlags unsupported = mods.maskInvert(allowed);
    if (unsupported.none())
        return Result::Continue;

    // Iterate over each bit in AstModifierFlagsE
    unsupported.forEachSet([&](AstModifierFlagsE flag) {
        TokenId tokId;
        switch (flag)
        {
            case AstModifierFlagsE::Bit: tokId = TokenId::ModifierBit; break;
            case AstModifierFlagsE::UnConst: tokId = TokenId::ModifierUnConst; break;
            case AstModifierFlagsE::Err: tokId = TokenId::ModifierErr; break;
            case AstModifierFlagsE::NoErr: tokId = TokenId::ModifierNoErr; break;
            case AstModifierFlagsE::Promote: tokId = TokenId::ModifierPromote; break;
            case AstModifierFlagsE::Wrap: tokId = TokenId::ModifierWrap; break;
            case AstModifierFlagsE::NoDrop: tokId = TokenId::ModifierNoDrop; break;
            case AstModifierFlagsE::Ref: tokId = TokenId::ModifierRef; break;
            case AstModifierFlagsE::ConstRef: tokId = TokenId::ModifierConstRef; break;
            case AstModifierFlagsE::Reverse: tokId = TokenId::ModifierReverse; break;
            case AstModifierFlagsE::Move: tokId = TokenId::ModifierMove; break;
            case AstModifierFlagsE::MoveRaw: tokId = TokenId::ModifierMoveRaw; break;
            case AstModifierFlagsE::Nullable: tokId = TokenId::ModifierNullable; break;
            default:
                SWC_UNREACHABLE();
        }

        // Find actual source token for the modifier
        const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
        const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {tokId});

        // Emit diagnostic
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_modifier_unsupported, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_WHAT, srcView.token(mdfRef).string(srcView));
        diag.last().addSpan(Diagnostic::tokenErrorLocation(sema.ctx(), srcView, mdfRef), "");
        diag.report(sema.ctx());
    });

    return Result::Error;
}

Result SemaCheck::isValue(Sema& sema, AstNodeRef nodeRef)
{
    const AstNode& node = sema.node(nodeRef);
    if (sema.isValue(node))
        return Result::Continue;
    return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeRef);
}

Result SemaCheck::isValueOrType(Sema& sema, SemaNodeView& nodeView)
{
    if (sema.isValue(*nodeView.node))
        return Result::Continue;
    if (nodeView.typeRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeView.nodeRef);

    const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), nodeView.typeRef));
    nodeView.setCstRef(sema, cstRef);
    sema.setConstant(nodeView.nodeRef, cstRef);
    return Result::Continue;
}

Result SemaCheck::isValueOrTypeInfo(Sema& sema, SemaNodeView& nodeView)
{
    if (sema.isValue(*nodeView.node))
        return Result::Continue;
    if (nodeView.typeRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeView.nodeRef);

    ConstantRef cstRef;
    RESULT_VERIFY(sema.cstMgr().makeTypeInfo(sema, cstRef, nodeView.typeRef, nodeView.nodeRef));
    nodeView.setCstRef(sema, cstRef);
    sema.setConstant(nodeView.nodeRef, cstRef);
    return Result::Continue;
}

Result SemaCheck::isConstant(Sema& sema, AstNodeRef nodeRef)
{
    if (!sema.hasConstant(nodeRef))
    {
        SemaError::raiseExprNotConst(sema, nodeRef);
        return Result::Error;
    }

    return Result::Continue;
}

Result SemaCheck::isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute)
{
    bool hasName    = false;
    bool hasDefault = false;
    for (size_t i = 0; i < parameters.size(); i++)
    {
        const SymbolVariable& param = *parameters[i];
        const TypeInfo&       type  = param.type(sema.ctx());

        if (attribute)
        {
            const TypeInfo* baseType = &type;
            if (type.isTypedVariadic())
                baseType = &sema.typeMgr().get(type.payloadTypeRef());

            bool allowed = false;
            if (baseType->isBool() ||
                baseType->isChar() ||
                baseType->isString() ||
                baseType->isInt() ||
                baseType->isFloat() ||
                baseType->isRune() ||
                baseType->isEnum() ||
                baseType->isTypeInfo() ||
                baseType->isType())
            {
                allowed = true;
            }

            if (!allowed)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_attribute_parameter_type, param.decl()->srcViewRef(), param.tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, type.toName(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        // Variadic must be last
        if (type.isAnyVariadic() && i != parameters.size() - 1)
            return SemaError::raise(sema, DiagnosticId::sema_err_variadic_not_last, param.decl()->srcViewRef(), param.tokRef());

        // A parameter without a default follows a parameter with a default value
        if (param.hasExtraFlag(SymbolVariableFlagsE::Initialized))
            hasDefault = true;
        else if (hasDefault)
            return SemaError::raise(sema, DiagnosticId::sema_err_parameter_default_value_not_last, param.decl()->srcViewRef(), param.tokRef());

        // If a parameter has a name, then what follows should have a name
        if (param.idRef().isValid())
            hasName = true;
        else if (hasName)
            return SemaError::raise(sema, DiagnosticId::sema_err_unnamed_parameter, param.decl()->srcViewRef(), param.tokRef());
    }

    return Result::Continue;
}

Result SemaCheck::isAssignable(Sema& sema, const AstNode& node, const SemaNodeView& leftView)
{
    // Disallow assignment to immutable lvalues:
    if (leftView.sym)
    {
        if (const auto* symVar = leftView.sym->safeCast<SymbolVariable>())
        {
            if (symVar->hasExtraFlag(SymbolVariableFlagsE::Let))
            {
                const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_let, node.srcViewRef(), node.tokRef());
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (leftView.sym->isConstant())
        {
            const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, node.srcViewRef(), node.tokRef());
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (leftView.type && leftView.type->isConst())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_immutable, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, leftView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Left must be a l-value
    if (!sema.isLValue(*leftView.node))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_not_lvalue, node.srcViewRef(), node.tokRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
