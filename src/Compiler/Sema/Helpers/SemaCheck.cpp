#include "pch.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isConstAssignmentTargetImpl(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView);

    bool isIgnoredValuePoison(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView symbolView = sema.viewSymbol(nodeRef);
        return symbolView.hasSymbol() && symbolView.sym() && symbolView.sym()->isIgnored();
    }

    bool isInlineConstAssignmentTarget(const Sema& sema, AstNodeRef nodeRef)
    {
        return sema.isConstAssignTargetStored(nodeRef);
    }

    bool isInlineConstAssignmentBinding(const Sema& sema, AstNodeRef nodeRef)
    {
        return sema.isConstAssignBindingStored(nodeRef);
    }

    bool shouldReadReferenceForBoolExpr(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return false;

        return sema.typeMgr().get(normalizedTypeRef).isReference();
    }

    AstNodeRef resolveNodeRefForCheck(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        AstNodeRef resolvedNodeRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedNodeRef.isInvalid())
            resolvedNodeRef = nodeRef;
        return resolvedNodeRef;
    }

    bool isConstTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isConst())
            return true;

        const TypeRef unwrappedTypeRef = type.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        return unwrappedTypeRef.isValid() && sema.typeMgr().get(unwrappedTypeRef).isConst();
    }

    bool isNonReassignableFunctionParameter(Sema& sema, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return false;
        if (!symVar.typeRef().isValid())
            return true;

        return !sema.typeMgr().get(symVar.typeRef()).isReference();
    }

    bool isReadOnlyAggregateFunctionParameter(Sema& sema, const SymbolVariable& symVar)
    {
        if (!isNonReassignableFunctionParameter(sema, symVar))
            return false;
        if (!symVar.typeRef().isValid())
            return true;

        const TypeInfo& typeInfo = sema.typeMgr().get(symVar.typeRef());
        return !typeInfo.isPointerLike() && !typeInfo.isArray();
    }

    bool canResolveFunctionParameterIdentifier(const Sema& sema, const SourceCodeRef& codeRef)
    {
        if (!codeRef.isValid())
            return false;

        const SourceView& srcView = sema.srcView(codeRef.srcViewRef);
        if (codeRef.tokRef.get() >= srcView.tokens().size())
            return false;

        const Token& tok = srcView.token(codeRef.tokRef);
        if (tok.id != TokenId::Identifier)
            return false;
        if (tok.byteStart >= srcView.identifiers().size())
            return false;

        const uint32_t byteStart = srcView.identifiers()[tok.byteStart].byteStart;
        return byteStart + tok.byteLength <= srcView.stringView().size();
    }

    const SymbolVariable* currentFunctionParameterByIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        if (!sema.isCurrentFunction() || nodeRef.isInvalid())
            return nullptr;
        if (!sema.node(nodeRef).is(AstNodeId::Identifier))
            return nullptr;

        const SourceCodeRef codeRef = sema.node(nodeRef).codeRef();
        if (!canResolveFunctionParameterIdentifier(sema, codeRef))
            return nullptr;

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), codeRef);
        for (const SymbolVariable* param : sema.currentFunction()->parameters())
        {
            if (param && param->idRef() == idRef)
                return param;
        }

        return nullptr;
    }

    bool isNonReassignableParameterIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        const SymbolVariable* param = currentFunctionParameterByIdentifier(sema, nodeRef);
        return param && isNonReassignableFunctionParameter(sema, *param);
    }

    bool isReadOnlyAggregateParameterIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        const SymbolVariable* param = currentFunctionParameterByIdentifier(sema, nodeRef);
        return param && isReadOnlyAggregateFunctionParameter(sema, *param);
    }

    bool isSyntheticAutoMemberLeft(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        return node.is(AstNodeId::Identifier) && node.codeRef().isValid() && sema.token(node.codeRef()).id == TokenId::SymDot;
    }

    bool isReadOnlyAggregateParameterPath(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, nodeRef);
        if (resolvedRef.isInvalid())
            return false;

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::Identifier))
            return isReadOnlyAggregateParameterIdentifier(sema, resolvedRef);
        if (node.is(AstNodeId::MemberAccessExpr))
        {
            const auto& member = node.cast<AstMemberAccessExpr>();
            return !isSyntheticAutoMemberLeft(sema, member.nodeLeftRef) && isReadOnlyAggregateParameterPath(sema, member.nodeLeftRef);
        }
        if (node.is(AstNodeId::IndexExpr))
            return isReadOnlyAggregateParameterPath(sema, node.cast<AstIndexExpr>().nodeExprRef);
        if (node.is(AstNodeId::IndexListExpr))
            return isReadOnlyAggregateParameterPath(sema, node.cast<AstIndexListExpr>().nodeExprRef);
        return false;
    }

    bool isConstSourceViewImpl(Sema& sema, const SemaNodeView& view)
    {
        if (isConstTypeRef(sema, view.typeRef()))
            return true;

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
        if (!sourceTypeRef.isValid())
            return false;

        const TypeInfo& sourceType = sema.typeMgr().get(sourceTypeRef);
        return sourceType.isString() || sourceType.isCString();
    }

    AstNodeRef indexedSourceRef(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedNodeRef = resolveNodeRefForCheck(sema, nodeRef);
        if (resolvedNodeRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(resolvedNodeRef);
        if (node.is(AstNodeId::IndexExpr))
            return node.cast<AstIndexExpr>().nodeExprRef;
        if (node.is(AstNodeId::IndexListExpr))
            return node.cast<AstIndexListExpr>().nodeExprRef;
        return AstNodeRef::invalid();
    }

    bool isConstIndexedSource(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef sourceRef = indexedSourceRef(sema, nodeRef);
        if (sourceRef.isInvalid())
            return false;

        const SemaNodeView sourceView = sema.viewNodeTypeConstantSymbol(sourceRef);
        if (isInlineConstAssignmentTarget(sema, sourceRef) || isConstAssignmentTargetImpl(sema, sourceRef, sourceView))
            return true;
        if (!sourceView.type())
            return false;
        if (isConstSourceViewImpl(sema, sourceView))
            return true;

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), sourceView.typeRef());
        if (!sourceTypeRef.isValid())
            return false;

        return sema.typeMgr().get(sourceTypeRef).isConst();
    }

    bool isDerefConstSource(Sema& sema, const AstUnaryExpr& node)
    {
        const Token& tok = sema.token(node.codeRef());
        if (tok.id != TokenId::KwdDRef)
            return false;

        const SemaNodeView sourceView = sema.viewTypeSymbol(node.nodeExprRef);
        return isConstSourceViewImpl(sema, sourceView);
    }

    Result normalizeTypeInfoValueIfNeeded(Sema& sema, SemaNodeView& view)
    {
        if (!SemaHelpers::isTypeLikeTypeRef(sema.ctx(), view.typeRef()))
            return Result::Continue;

        bool        changed = false;
        ConstantRef cstRef  = view.cstRef();
        if (cstRef.isValid())
        {
            SWC_RESULT(SemaHelpers::normalizeTypeInfoConstantRef(sema, cstRef, view.nodeRef()));
            if (cstRef != view.cstRef())
            {
                sema.setConstant(view.nodeRef(), cstRef);
                changed = true;
            }
        }

        const TypeRef typeRef = SemaHelpers::normalizeTypeLikeValueTypeRef(sema, view.typeRef(), cstRef, view.nodeRef());
        if (typeRef.isValid() && typeRef != view.typeRef())
        {
            sema.setType(view.nodeRef(), typeRef);
            changed = true;
        }

        if (changed)
            view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return Result::Continue;
    }

    bool isConstAssignmentTargetImpl(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView)
    {
        SWC_UNUSED(leftView);

        if (isInlineConstAssignmentTarget(sema, leftExprRef))
            return true;

        const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, leftExprRef);
        if (resolvedRef.isInvalid())
            return false;

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::MemberAccessExpr))
        {
            const auto&        member     = node.cast<AstMemberAccessExpr>();
            const SemaNodeView sourceView = sema.viewNodeTypeConstantSymbol(member.nodeLeftRef);
            return (!isSyntheticAutoMemberLeft(sema, member.nodeLeftRef) && isConstSourceViewImpl(sema, sourceView)) || isConstAssignmentTargetImpl(sema, member.nodeLeftRef, sourceView);
        }
        if (node.is(AstNodeId::IndexExpr) || node.is(AstNodeId::IndexListExpr))
            return isConstIndexedSource(sema, resolvedRef);
        if (node.is(AstNodeId::UnaryExpr))
            return isDerefConstSource(sema, node.cast<AstUnaryExpr>());
        return false;
    }

    TokenId tokenIdForModifierFlag(AstModifierFlagsE flag)
    {
        switch (flag)
        {
            case AstModifierFlagsE::Bit: return TokenId::ModifierBit;
            case AstModifierFlagsE::UnConst: return TokenId::ModifierUnConst;
            case AstModifierFlagsE::Err: return TokenId::ModifierErr;
            case AstModifierFlagsE::NoErr: return TokenId::ModifierNoErr;
            case AstModifierFlagsE::Promote: return TokenId::ModifierPromote;
            case AstModifierFlagsE::Wrap: return TokenId::ModifierWrap;
            case AstModifierFlagsE::NoDrop: return TokenId::ModifierNoDrop;
            case AstModifierFlagsE::Ref: return TokenId::ModifierRef;
            case AstModifierFlagsE::ConstRef: return TokenId::ModifierConstRef;
            case AstModifierFlagsE::Reverse: return TokenId::ModifierReverse;
            case AstModifierFlagsE::Move: return TokenId::ModifierMove;
            case AstModifierFlagsE::MoveRaw: return TokenId::ModifierMoveRaw;
            case AstModifierFlagsE::Nullable: return TokenId::ModifierNullable;
            default:
                SWC_UNREACHABLE();
        }
    }

    void reportUnsupportedModifier(Sema& sema, const AstNode& node, AstModifierFlagsE flag)
    {
        const TokenId     tokId   = tokenIdForModifierFlag(flag);
        const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
        const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {tokId});

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_modifier_unsupported, node.codeRef());
        diag.addArgument(Diagnostic::ARG_WHAT, srcView.tokenString(mdfRef));
        diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), mdfRef), "");
        diag.report(sema.ctx());
    }
}

Result SemaCheck::modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed)
{
    const AstModifierFlags unsupported = mods.maskInvert(allowed);
    if (unsupported.none())
        return Result::Continue;

    unsupported.forEachSet([&](AstModifierFlagsE flag) { reportUnsupportedModifier(sema, node, flag); });

    return Result::Error;
}

Result SemaCheck::isValue(Sema& sema, AstNodeRef nodeRef)
{
    if (sema.isValue(nodeRef))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, nodeRef))
        return Result::Error;
    return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeRef);
}

Result SemaCheck::isValueOrType(Sema& sema, SemaNodeView& view)
{
    if (sema.isValue(view.nodeRef()))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, view.nodeRef()))
        return Result::Error;
    if (view.typeRef().isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), view.typeRef()));
    sema.setConstant(view.nodeRef(), cstRef);
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    return Result::Continue;
}

Result SemaCheck::isValueOrTypeInfo(Sema& sema, SemaNodeView& view)
{
    if (sema.isValue(view.nodeRef()))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, view.nodeRef()))
        return Result::Error;
    if (view.typeRef().isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    ConstantRef cstRef;
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, cstRef, view.typeRef(), view.nodeRef()));
    sema.setConstant(view.nodeRef(), cstRef);
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    return Result::Continue;
}

Result SemaCheck::prepareBoolExprValue(Sema& sema, SemaNodeView& view)
{
    SWC_RESULT(isValueOrTypeInfo(sema, view));
    SWC_RESULT(normalizeTypeInfoValueIfNeeded(sema, view));

    if (!shouldReadReferenceForBoolExpr(sema, view.typeRef()))
        return Result::Continue;

    const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
    const TypeRef valueTypeRef      = sema.typeMgr().get(normalizedTypeRef).payloadTypeRef();
    SWC_RESULT(Cast::cast(sema, view, valueTypeRef, CastKind::Implicit));
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    return Result::Continue;
}

Result SemaCheck::castToBool(Sema& sema, SemaNodeView& view)
{
    const bool representedTypeValue = SemaHelpers::resolveRepresentedTypeRef(sema, view).isValid();
    SWC_RESULT(prepareBoolExprValue(sema, view));
    SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));

    if (representedTypeValue)
    {
        const SemaNodeView castView = sema.viewNodeTypeConstant(view.nodeRef());
        if (castView.cstRef().isInvalid() || !sema.cstMgr().get(castView.cstRef()).isBool())
        {
            sema.setConstant(view.nodeRef(), sema.cstMgr().cstTrue());
            view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }
    }

    return Result::Continue;
}

Result SemaCheck::isConstant(Sema& sema, AstNodeRef nodeRef)
{
    const SemaNodeView view = sema.viewConstant(nodeRef);
    if (view.cstRef().isInvalid())
    {
        SemaError::raiseExprNotConst(sema, nodeRef);
        return Result::Error;
    }

    return Result::Continue;
}

Result SemaCheck::isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute)
{
    bool                  hasName             = false;
    bool                  hasDefault          = false;
    const SymbolVariable* previousDefaultParm = nullptr;
    for (size_t i = 0; i < parameters.size(); i++)
    {
        const SymbolVariable& param = *(parameters[i]);
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
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_attribute_parameter_type, param);
                diag.addArgument(Diagnostic::ARG_TYPE, type.toName(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        // Variadic must be last
        if (type.isAnyVariadic() && i != parameters.size() - 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_variadic_not_last, param);
            if (param.idRef().isValid() && parameters[i + 1]->idRef().isValid())
                diag.addArgument(Diagnostic::ARG_VALUE, parameters[i + 1]->name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        // A parameter without a default follows a parameter with a default value
        if (param.hasExtraFlag(SymbolVariableFlagsE::Initialized))
        {
            hasDefault          = true;
            previousDefaultParm = &param;
        }
        else if (hasDefault && !type.isCodeBlock())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_parameter_default_value_not_last, param);
            if (param.idRef().isValid() && previousDefaultParm && previousDefaultParm->idRef().isValid())
                diag.addArgument(Diagnostic::ARG_VALUE, previousDefaultParm->name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        // If a parameter has a name, then what follows should have a name
        if (param.idRef().isValid())
            hasName = true;
        else if (hasName)
            return SemaError::raise(sema, DiagnosticId::sema_err_unnamed_parameter, param);
    }

    return Result::Continue;
}

Result SemaCheck::isAssignable(Sema& sema, AstNodeRef errorNodeRef, AstNodeRef leftExprRef, const SemaNodeView& leftView, const bool allowLetReferenceWriteThrough)
{
    if (isInlineConstAssignmentBinding(sema, leftExprRef))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, errorNodeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Disallow assignment to immutable lvalues:
    if (leftView.sym())
    {
        if (leftView.sym()->isLetVariable())
        {
            const bool canWriteThroughReference = allowLetReferenceWriteThrough &&
                                                  leftView.type() &&
                                                  leftView.type()->isReference();
            if (!canWriteThroughReference)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_let, errorNodeRef);
                SemaError::setReportArguments(sema, diag, leftView.sym());
                diag.addNote(DiagnosticId::sema_note_let_variable_declared_here);
                diag.last().addArgument(Diagnostic::ARG_SYM, leftView.sym()->name(sema.ctx()));
                diag.last().addSpan(leftView.sym()->codeRange(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (leftView.sym()->isConstant())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, errorNodeRef);
            SemaError::setReportArguments(sema, diag, leftView.sym());
            diag.addNote(DiagnosticId::sema_note_constant_declared_here);
            diag.last().addArgument(Diagnostic::ARG_SYM, leftView.sym()->name(sema.ctx()));
            diag.last().addSpan(leftView.sym()->codeRange(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (isNonReassignableParameterIdentifier(sema, leftExprRef) || isReadOnlyAggregateParameterPath(sema, leftExprRef))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, errorNodeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (isConstAssignmentTarget(sema, leftExprRef, leftView))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, errorNodeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Left must be a l-value
    if (!sema.isLValue(leftExprRef) && !sema.isLValueStored(leftExprRef))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_not_lvalue, errorNodeRef);
        diag.addNote(DiagnosticId::sema_note_expression_not_assignable);
        SemaError::addSpan(sema, diag.last(), leftExprRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    return Result::Continue;
}

bool SemaCheck::isConstAssignmentTarget(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView)
{
    return isConstAssignmentTargetImpl(sema, leftExprRef, leftView);
}

bool SemaCheck::isReadOnlyParameterPath(Sema& sema, AstNodeRef nodeRef)
{
    return isReadOnlyAggregateParameterPath(sema, nodeRef);
}

SWC_END_NAMESPACE();
