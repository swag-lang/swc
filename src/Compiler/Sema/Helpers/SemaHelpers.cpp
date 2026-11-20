#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

bool SemaHelpers::isByValueAggregateType(const TypeInfo& typeInfo)
{
    return typeInfo.isStructOrArray() || typeInfo.isAggregate();
}

bool SemaHelpers::isVariadicTypeRefOrAlias(Sema& sema, TypeRef typeRef)
{
    if (typeRef.isInvalid())
        return false;

    return sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef).isAnyVariadic();
}

bool SemaHelpers::isVariadicTypeNode(Sema& sema, AstNodeRef typeNodeRef)
{
    if (typeNodeRef.isInvalid())
        return false;

    const AstNode& typeNode = sema.node(typeNodeRef);
    if (typeNode.is(AstNodeId::VariadicType) || typeNode.is(AstNodeId::TypedVariadicType))
        return true;

    return isVariadicTypeRefOrAlias(sema, structuralTypeRefFromTypeNode(sema, typeNodeRef));
}

void SemaHelpers::addCurrentScopeSymbol(Sema& sema, Symbol* sym)
{
    SemaScope* scope = currentLocalSymbolScope(sema);
    SWC_ASSERT(scope);

    scope->addSymbol(sym);
    sema.compiler().notifyAlive();
}

namespace
{
    AstNodeRef transparentCastExprOperandRef(const AstNode& node)
    {
        switch (node.id())
        {
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
        // Dynamic conversions can produce null from a present box containing a null pointer.
        if (node.is(AstNodeId::CastExpr) && (node.cast<AstCastExpr>().modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}) || node.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::Fallible)))
            return AstNodeRef::invalid();
        if (node.is(AstNodeId::AsCastExpr))
            return AstNodeRef::invalid();

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

    template<auto OperandRef>
    AstNodeRef resolveTransparentSourceRef(Sema& sema, AstNodeRef nodeRef)
    {
        AstNodeRef sourceRef = nodeRef;
        while (sourceRef.isValid())
        {
            const AstNodeRef nextRef = OperandRef(sema.node(sourceRef));
            if (nextRef.isInvalid())
                return sourceRef;

            sourceRef = nextRef;
        }

        return AstNodeRef::invalid();
    }
}

TypeRef SemaHelpers::signalOwnerTypeRef(Sema& sema, AstNodeRef signalRef)
{
    if (signalRef.isInvalid())
        return TypeRef::invalid();

    const auto* member = sema.node(sema.resolvedNodeRef(signalRef)).safeCast<AstMemberAccessExpr>();
    if (!member)
        return TypeRef::invalid();

    TaskContext&    ctx   = sema.ctx();
    const TypeInfo* owner = &sema.typeMgr().get(unwrapBindingType(ctx, sema.viewType(member->nodeLeftRef).typeRef()));
    if (owner->isAnyPointer())
        owner = &sema.typeMgr().get(unwrapBindingType(ctx, owner->payloadTypeRef()));

    return owner->isStruct() ? owner->typeRef() : TypeRef::invalid();
}

Result SemaHelpers::signalCallbackTypeForOwner(Sema& sema, TypeRef callbackTypeRef, TypeRef ownerTypeRef, AstNodeRef waitNodeRef, TypeRef& outTypeRef)
{
    outTypeRef = callbackTypeRef;

    TaskContext&    ctx      = sema.ctx();
    TypeManager&    typeMgr  = sema.typeMgr();
    const TypeInfo& callback = typeMgr.get(unwrapBindingType(ctx, callbackTypeRef));
    if (!callback.isFunction() || callback.payloadSymFunction().parameters().empty())
        return Result::Continue;

    const SymbolFunction& declared      = callback.payloadSymFunction();
    const TypeInfo&       declaredFirst = typeMgr.get(declared.parameters().front()->typeRef());
    if (!declaredFirst.isValuePointer())
        return Result::Continue;

    const TypeInfo& declaredOwner = typeMgr.get(unwrapBindingType(ctx, declaredFirst.payloadTypeRef()));
    const TypeInfo& owner         = typeMgr.get(ownerTypeRef);
    if (!declaredOwner.isStruct() || &owner == &declaredOwner)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(&owner, waitNodeRef));
    SWC_RESULT(sema.waitSemaCompleted(&declaredOwner, waitNodeRef));
    if (!owner.payloadSymStruct().startsWith(ctx, declaredOwner.payloadSymStruct()))
        return Result::Continue;

    auto* symFunc = Symbol::make<SymbolFunction>(ctx, declared.decl(), declared.tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    for (const SymbolVariable* param : declared.parameters())
    {
        auto* symVar = Symbol::make<SymbolVariable>(ctx, param->decl(), param->tokRef(), param->idRef(), SymbolFlagsE::Zero);
        if (param == declared.parameters().front())
            symVar->setTypeRef(typeMgr.addType(TypeInfo::makeValuePointer(ownerTypeRef, declaredFirst.flags())));
        else
            symVar->setTypeRef(param->typeRef());
        symFunc->addParameter(symVar);
    }

    symFunc->setVariadicParamFlag(ctx);
    symFunc->setReturnTypeRef(declared.returnTypeRef());
    symFunc->assignExtraFlags(declared.extraFlags());
    symFunc->setCallConvKind(declared.callConvKind());

    outTypeRef = typeMgr.addType(TypeInfo::makeFunction(symFunc, callback.flags()));
    symFunc->setTypeRef(outTypeRef);
    symFunc->setDeclared(ctx);
    symFunc->setTyped(ctx);
    symFunc->setSemaCompleted(ctx);
    return Result::Continue;
}

TypeRef SemaHelpers::unwrapBindingType(TaskContext& ctx, TypeRef typeRef)
{
    while (typeRef.isValid())
    {
        const TypeInfo* typeInfo = &ctx.typeMgr().get(typeRef);
        if (const TypeInfo* unwrappedType = typeInfo->unwrapAliasEnumType(ctx))
        {
            typeRef  = unwrappedType->typeRef();
            typeInfo = unwrappedType;
        }

        if (typeInfo->isReference())
        {
            typeRef = typeInfo->payloadTypeRef();
            continue;
        }

        break;
    }

    return typeRef;
}

bool SemaHelpers::mergeCompatibleFunctionBindingType(const TypeRef bindingTypeRef, const TypeRef resolvedTypeRef, TypeRef& outBindingTypeRef, TypeRef& compareTypeRef)
{
    if (compareTypeRef.isInvalid())
    {
        outBindingTypeRef = bindingTypeRef;
        compareTypeRef    = resolvedTypeRef;
        return true;
    }

    if (compareTypeRef == resolvedTypeRef)
        return true;

    outBindingTypeRef = TypeRef::invalid();
    return false;
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
        const TypeInfo* typeInfo = &ctx.typeMgr().get(typeRef);
        if (typeInfo->isAlias())
        {
            if (const TypeInfo* unwrappedType = typeInfo->unwrapAliasType(ctx))
            {
                typeRef  = unwrappedType->typeRef();
                typeInfo = unwrappedType;
            }
        }

        if (typeInfo->isReference())
        {
            typeRef = typeInfo->payloadTypeRef();
            continue;
        }

        break;
    }

    return typeRef;
}

SymbolFunction* SemaHelpers::callableTypeFunction(TaskContext& ctx, TypeRef typeRef)
{
    typeRef = unwrapBindingType(ctx, typeRef);
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
        const TypeRef bindingTypeRef = unwrapBindingType(sema.ctx(), bindingTypes[bindingIndex - 1]);
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

        default:
            return false;
    }
}

// Check constant amounts even when the shifted value is runtime. Reject negative
// or oversized amounts here so shifts by constants need no runtime guard.
Result SemaHelpers::checkConstantShiftAmount(Sema& sema, AstNodeRef nodeRef, const TypeInfo& valueType, const SemaNodeView& amountView, AstNodeRef amountNodeRef)
{
    if (!amountView.hasConstant() || !valueType.isInt() || valueType.isIntUnsized())
        return Result::Continue;

    const ConstantValue& amountCst = *amountView.cst();
    if (!amountCst.isInt())
        return Result::Continue;

    const ApsInt&    amount = amountCst.getInt();
    const uint32_t   width  = valueType.payloadIntLikeBits();
    Math::FoldStatus status = Math::FoldStatus::Ok;
    if (amount.isNegative())
        status = Math::FoldStatus::NegativeShift;
    else if (!amount.fits64() || amount.as64() >= width)
        status = Math::FoldStatus::LargeShift;

    if (status == Math::FoldStatus::Ok)
        return Result::Continue;

    // Inside an inline expansion the shift may be dead for these arguments; the runtime guard
    // then answers, as it does for a whole constant shift whose fold is declined there.
    if (!sema.isConstExprRequired() && sema.frame().currentInlinePayload() != nullptr)
        return Result::Continue;

    auto diag = SemaError::reportFoldSafety(sema, status, nodeRef, SemaError::ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_RIGHT, amountView.cstRef());

    const DiagnosticId labelId = status == Math::FoldStatus::NegativeShift ? DiagnosticId::sema_note_negative_shift_amount_here : DiagnosticId::sema_note_large_shift_amount_here;
    diag.last().addSpan(sema.node(amountNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast()), labelId, DiagnosticSeverity::Note);
    diag.report(sema.ctx());

    return Result::Error;
}

// Contextual types belong to the enclosing expression, not each nested statement:
// the u8 in var x: u8 = #run { ... } constrains the result. Clear bindings in the
// existing frame so statement narrowing facts survive; return supplies its own type.
void SemaHelpers::scopeBindingsForStatement(Sema& sema)
{
    sema.frame().clearBindingTypes();
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

bool SemaHelpers::bindingSymbolResolvesStandalone(Sema& sema, const SymbolVariable& symVar)
{
    if (symVar.hasGlobalStorage())
        return true;

    // An instance field only exists relative to a base expression.
    if (symVar.ownerSymMap() && symVar.ownerSymMap()->isStruct())
        return false;

    // Parameters resolve by position in their owning function. A macro receiver
    // from another function has no storage here and could otherwise be remapped
    // by name to an unrelated caller parameter.
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        const SymbolFunction* fn = sema.currentFunction();
        if (!fn)
            return false;

        const auto& params = fn->parameters();
        const auto  index  = symVar.parameterIndex();
        if (index < params.size() && params[index] == &symVar)
            return true;

        return std::ranges::find(params, &symVar) != params.end();
    }

    return true;
}

bool SemaHelpers::isTransparentExprNode(const AstNode& node)
{
    return transparentConditionExprOperandRef(node).isValid();
}

AstNodeRef SemaHelpers::resolveTransparentExprSourceRef(Sema& sema, AstNodeRef nodeRef)
{
    return resolveTransparentSourceRef<transparentCastExprOperandRef>(sema, nodeRef);
}

AstNodeRef SemaHelpers::resolveTransparentConditionExprSourceRef(Sema& sema, AstNodeRef nodeRef)
{
    return resolveTransparentSourceRef<transparentConditionExprOperandRef>(sema, nodeRef);
}

namespace
{
    // Follow substitutes and transparent wrappers to the expression carrying the fact.
    AstNodeRef resolveNarrowSourceRef(Sema& sema, AstNodeRef nodeRef)
    {
        for (int depth = 0; depth < 16 && nodeRef.isValid(); depth++)
        {
            const AstNodeRef resolvedRef = sema.resolvedNodeRef(nodeRef);
            if (resolvedRef.isValid())
                nodeRef = resolvedRef;

            const AstNodeRef unwrappedRef = SemaHelpers::resolveTransparentConditionExprSourceRef(sema, nodeRef);
            if (unwrappedRef.isValid() && unwrappedRef != nodeRef)
            {
                nodeRef = unwrappedRef;
                continue;
            }

            break;
        }

        return nodeRef;
    }

    bool typeRefIsNullable(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        return sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef).isNullable();
    }

    // A fact only attaches to a path whose declared type can carry it.
    bool narrowTypeAcceptsKind(Sema& sema, TypeRef typeRef, SemaNarrowFactKind kind)
    {
        if (!typeRef.isValid())
            return false;

        switch (kind)
        {
            case SemaNarrowFactKind::NonNull:
                return sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef).isNullable();

            case SemaNarrowFactKind::NonZero:
                return sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef).isIntLike();

            case SemaNarrowFactKind::Case:
                return false;
        }

        return false;
    }

    bool isNarrowRootVariable(Sema& sema, const SymbolVariable& symVar)
    {
        // A read-only value capture owns a stable copy, just like a local 'let'. A
        // reference capture or mutable environment can change through another caller.
        if (symVar.isClosureCapture())
            return !symVar.closureCaptureByRef() && symVar.hasExtraFlag(SymbolVariableFlagsE::Let);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) || symVar.hasGlobalStorage())
        {
            // Inlining can substitute a global for an already-validated receiver
            // parameter. Preserve the callee's local narrowing proof.
            const SemaInlinePayload* inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
            if (!inlinePayload || !inlinePayload->sourceFunction)
                return false;

            const AttributeList& attributes = inlinePayload->sourceFunction->attributes();
            if (attributes.hasMacroOrMixin())
                return false;

            return true;
        }

        return symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::Let) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
               symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal);
    }

    bool narrowOperandIsNullLiteral(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = resolveNarrowSourceRef(sema, nodeRef);
        if (!resolvedRef.isValid())
            return false;

        if (sema.node(resolvedRef).is(AstNodeId::NullLiteral))
            return true;

        const SemaNodeView view = sema.view(resolvedRef, SemaNodeViewPartE::Type);
        return view.typeRef().isValid() && view.type()->isNull();
    }

    bool narrowOperandIsZeroLiteral(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = resolveNarrowSourceRef(sema, nodeRef);
        if (!resolvedRef.isValid())
            return false;

        const SemaNodeView view = sema.view(resolvedRef, SemaNodeViewPartE::Constant);
        return view.hasConstant() && view.cst()->isInt() && view.cst()->getInt().isZero();
    }

    // The literal a comparison must be made against for the fact to be provable.
    bool narrowOperandIsSentinel(Sema& sema, AstNodeRef nodeRef, SemaNarrowFactKind kind)
    {
        switch (kind)
        {
            case SemaNarrowFactKind::NonNull:
                return narrowOperandIsNullLiteral(sema, nodeRef);

            case SemaNarrowFactKind::NonZero:
                return narrowOperandIsZeroLiteral(sema, nodeRef);

            case SemaNarrowFactKind::Case:
                return false;
        }

        return false;
    }

    void appendNarrowFact(SmallVector2<SemaNarrowFact>& facts, SmallVector4<const Symbol*>& path, SemaNarrowFactKind kind)
    {
        auto& fact = facts.emplace_back();
        fact.path.assign(path.begin(), path.end());
        fact.kind  = kind;
        fact.holds = true;
    }

    void collectNarrowGuardFromExpr(Sema& sema, AstNodeRef exprRef, SemaNarrowFactKind kind, SmallVector2<SemaNarrowFact>& facts)
    {
        const AstNodeRef resolvedRef = resolveNarrowSourceRef(sema, exprRef);
        if (!resolvedRef.isValid())
            return;

        SmallVector4<const Symbol*> path;
        if (!SemaHelpers::extractNarrowPath(sema, resolvedRef, path))
            return;

        // Use the path's declared type: the condition node may already have
        // been converted to bool by the truthiness check.
        if (!narrowTypeAcceptsKind(sema, path.back()->typeRef(), kind))
            return;

        appendNarrowFact(facts, path, kind);
    }

    void appendNarrowCaseFact(SmallVector2<SemaNarrowFact>& facts, const SmallVector4<const Symbol*>& path, std::span<const ConstantRef> cases)
    {
        auto& fact = facts.emplace_back();
        fact.path.assign(path.begin(), path.end());
        fact.cases = cases;
        fact.kind  = SemaNarrowFactKind::Case;
        fact.holds = true;
    }

    // The tag holds the case on the true edge and any other value on the false one.
    void collectTaggedCaseGuard(Sema& sema, const SymbolStruct& tagged, const SmallVector4<const Symbol*>& path, ConstantRef caseRef, bool equal, SemaHelpers::NarrowGuards& out)
    {
        const std::array                   oneCase{caseRef};
        const std::span<const ConstantRef> holds  = SemaTagged::copyCases(sema, oneCase);
        const std::span<const ConstantRef> others = SemaTagged::complementCases(sema, tagged, holds);
        appendNarrowCaseFact(equal ? out.whenTrue : out.whenFalse, path, holds);
        appendNarrowCaseFact(equal ? out.whenFalse : out.whenTrue, path, others);
    }

    // 'Swag.kindOf(u) == .A' (either side): the comparison proves the case of 'u'.
    bool collectKindOfComparisonGuard(Sema& sema, const AstRelationalExpr& relational, TokenId op, SemaHelpers::NarrowGuards& out)
    {
        for (const auto& [subjectRef, valueRef] : {std::pair{relational.nodeLeftRef, relational.nodeRightRef}, std::pair{relational.nodeRightRef, relational.nodeLeftRef}})
        {
            SmallVector4<const Symbol*> path;
            const SymbolStruct*         tagged = SemaTagged::kindOfSubject(sema, subjectRef, path);
            if (!tagged)
                continue;

            const SemaNodeView valueView = sema.viewConstant(valueRef);
            if (!valueView.hasConstant())
                return false;

            collectTaggedCaseGuard(sema, *tagged, path, valueView.cstRef(), op == TokenId::SymEqualEqual, out);
            return true;
        }

        return false;
    }

    // != sentinel proves the true edge; == sentinel proves the false edge.
    // A missing sentinel returns false so the caller can try another fact kind.
    bool collectSentinelComparisonGuard(Sema& sema, const AstRelationalExpr& relational, TokenId op, SemaNarrowFactKind kind, SemaHelpers::NarrowGuards& out)
    {
        const bool leftIsSentinel  = narrowOperandIsSentinel(sema, relational.nodeLeftRef, kind);
        const bool rightIsSentinel = narrowOperandIsSentinel(sema, relational.nodeRightRef, kind);
        if (leftIsSentinel == rightIsSentinel)
            return false;

        const AstNodeRef targetRef = leftIsSentinel ? relational.nodeRightRef : relational.nodeLeftRef;
        collectNarrowGuardFromExpr(sema, targetRef, kind, op == TokenId::SymBangEqual ? out.whenTrue : out.whenFalse);

        return true;
    }
}

bool SemaHelpers::extractNarrowPath(Sema& sema, AstNodeRef nodeRef, SmallVector4<const Symbol*>& outPath)
{
    if (nodeRef.isInvalid())
        return false;

    // Transparent wrappers and substitutes preserve the accessed storage path.
    const AstNodeRef resolvedRef = resolveNarrowSourceRef(sema, nodeRef);
    if (!resolvedRef.isValid())
        return false;

    const AstNode& node = sema.node(resolvedRef);
    if (node.is(AstNodeId::ParenExpr))
        return extractNarrowPath(sema, node.cast<AstParenExpr>().nodeExprRef, outPath);

    if (node.is(AstNodeId::MemberAccessExpr))
    {
        const auto& member = node.cast<AstMemberAccessExpr>();
        if (!extractNarrowPath(sema, member.nodeLeftRef, outPath))
            return false;

        const SemaNodeView rightView = sema.view(member.nodeRightRef, SemaNodeViewPartE::Symbol);
        const Symbol*      rightSym  = rightView.singleSymbol();
        if (!rightSym || !rightSym->isVariable())
            return false;
        if (rightSym->cast<SymbolVariable>().hasGlobalStorage())
            return false;

        outPath.push_back(rightSym);

        return true;
    }

    const SemaNodeView view = sema.view(resolvedRef, SemaNodeViewPartE::Symbol);
    const Symbol*      sym  = view.singleSymbol();
    if (!sym || !sym->isVariable())
        return false;
    if (!isNarrowRootVariable(sema, sym->cast<SymbolVariable>()))
        return false;

    outPath.push_back(sym);

    return true;
}

void SemaHelpers::collectNarrowGuards(Sema& sema, AstNodeRef condRef, NarrowGuards& out)
{
    const AstNodeRef resolvedRef = resolveNarrowSourceRef(sema, condRef);
    if (!resolvedRef.isValid())
        return;

    const AstNode& node = sema.node(resolvedRef);
    switch (node.id())
    {
        case AstNodeId::UnaryExpr:
        {
            const auto& unary = node.cast<AstUnaryExpr>();
            if (sema.token(unary.codeRef()).id != TokenId::KwdNot)
                return;

            NarrowGuards child;
            collectNarrowGuards(sema, unary.nodeExprRef, child);

            for (auto& fact : child.whenTrue)
                out.whenFalse.push_back(std::move(fact));

            for (auto& fact : child.whenFalse)
                out.whenTrue.push_back(std::move(fact));

            return;
        }

        case AstNodeId::LogicalExpr:
        {
            const auto&  logical = node.cast<AstLogicalExpr>();
            NarrowGuards left;
            NarrowGuards right;

            collectNarrowGuards(sema, logical.nodeLeftRef, left);
            collectNarrowGuards(sema, logical.nodeRightRef, right);

            const TokenId op = sema.token(logical.codeRef()).id;
            if (op == TokenId::KwdAnd)
            {
                // Both operands are true on the true edge of and.
                for (auto& fact : left.whenTrue)
                    out.whenTrue.push_back(std::move(fact));
                for (auto& fact : right.whenTrue)
                    out.whenTrue.push_back(std::move(fact));
            }
            else if (op == TokenId::KwdOr)
            {
                // Both operands are false on the false edge of or.
                for (auto& fact : left.whenFalse)
                    out.whenFalse.push_back(std::move(fact));
                for (auto& fact : right.whenFalse)
                    out.whenFalse.push_back(std::move(fact));
            }

            return;
        }

        case AstNodeId::RelationalExpr:
        {
            const auto&   relational = node.cast<AstRelationalExpr>();
            const TokenId op         = sema.token(relational.codeRef()).id;
            if (op != TokenId::SymEqualEqual && op != TokenId::SymBangEqual)
                return;

            if (collectKindOfComparisonGuard(sema, relational, op, out))
                return;
            if (collectSentinelComparisonGuard(sema, relational, op, SemaNarrowFactKind::NonNull, out))
                return;

            collectSentinelComparisonGuard(sema, relational, op, SemaNarrowFactKind::NonZero, out);
            return;
        }

        case AstNodeId::IsTypeExpr:
        {
            const auto* payload = sema.semaPayload<TaggedIsPayload>(resolvedRef);
            if (!payload)
                return;

            SmallVector4<const Symbol*> path;
            const AstNodeRef            subjectRef = node.cast<AstIsTypeExpr>().nodeExprRef;
            if (SemaTagged::extractUnionPath(sema, subjectRef, sema.viewType(subjectRef).typeRef(), *payload->tagged, path))
                collectTaggedCaseGuard(sema, *payload->tagged, path, payload->caseRef, true, out);
            return;
        }

        default:
            // Bare truthiness infers only presence. Require != 0 for non-zero
            // proofs, avoiding unused facts on common conditions such as if count.
            collectNarrowGuardFromExpr(sema, resolvedRef, SemaNarrowFactKind::NonNull, out.whenTrue);
    }
}

TypeRef SemaHelpers::nullCoalescingResultType(Sema& sema, const TypeRef leftTypeRef, const TypeRef rightTypeRef)
{
    const TypeInfo& rawLeftType         = sema.typeMgr().get(leftTypeRef);
    const TypeInfo& leftType            = rawLeftType.unwrapAliasTypeOrSelf(sema.ctx());
    const TypeRef   concreteLeftTypeRef = leftType.typeRef();
    if (!leftType.isSupportsNullableQualifier() || leftType.isNonNullable())
        return leftTypeRef;

    // The left branch is selected only when it is present, so the fallback
    // determines the result contract. An explicit non-null lhs remains non-null.
    const TypeInfo& rawRightType         = sema.typeMgr().get(rightTypeRef);
    const TypeInfo& rightType            = rawRightType.unwrapAliasTypeOrSelf(sema.ctx());
    const TypeRef   concreteRightTypeRef = rightType.typeRef();
    if (rightType.isNull() || rightType.isNullable())
        return leftTypeRef;

    TypeInfo resultType = leftType;
    resultType.removeFlag(TypeInfoFlagsE::Nullable);

    const TypeRef resultTypeRef = sema.typeMgr().addType(resultType);
    if (resultTypeRef == concreteLeftTypeRef)
        return leftTypeRef;

    // Narrowing the left changes its concrete type. When the fallback already has
    // that exact result type, keep its alias rather than implicitly stripping it.
    return resultTypeRef == concreteRightTypeRef ? rightTypeRef : resultTypeRef;
}

// The caller enters only with a valid type and active flow-narrowing facts.
TypeRef SemaHelpers::nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
{
    // Preserve alias identity by clearing Nullable on the original type; unwrap
    // only to find a hidden flag. Most types are not nullable, so reject them
    // before reading the current node.
    const TypeInfo* nullableType = &sema.typeMgr().get(typeRef);
    if (!nullableType->isNullable())
    {
        nullableType = nullableType->unwrapAliasEnumType(sema.ctx());
        if (!nullableType || !nullableType->isNullable())
            return TypeRef::invalid();
    }

    // An assignment target keeps its declared type: narrowing applies to reads, not
    // writes (otherwise `x = <nullable>` inside a guard would reject its own kill).
    const AstNodeRef curRef = sema.curNodeRef();
    if (curRef.isValid())
    {
        const AstNode& curNode = sema.node(curRef);
        if (curNode.is(AstNodeId::AssignStmt))
        {
            const auto& assign = curNode.cast<AstAssignStmt>();
            if (sema.token(assign.codeRef()).id == TokenId::SymEqual)
            {
                const AstNodeRef leftRef = sema.resolvedNodeRef(assign.nodeLeftRef);
                if (leftRef == nodeRef)
                    return TypeRef::invalid();

                // Multi-assign: each individual target of the list keeps its declared type.
                if (leftRef.isValid() && sema.node(leftRef).is(AstNodeId::AssignList))
                {
                    const SpanRef targetsRef = sema.node(leftRef).cast<AstAssignList>().spanChildrenRef;
                    if (sema.ast().hasSpan(targetsRef))
                    {
                        const auto targets = sema.ast().nodeSpan(targetsRef);
                        for (auto chunk = targets.chunksBegin(); chunk != targets.chunksEnd(); ++chunk)
                        {
                            for (const AstNodeRef targetRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
                            {
                                if (sema.resolvedNodeRef(targetRef) == nodeRef)
                                    return TypeRef::invalid();
                            }
                        }
                    }
                }
            }
        }
    }

    SmallVector4<const Symbol*> path;
    if (!extractNarrowPath(sema, nodeRef, path))
        return TypeRef::invalid();

    if (!sema.frame().queryNarrowFact({path.data(), path.size()}, SemaNarrowFactKind::NonNull))
        return TypeRef::invalid();

    TypeInfo resultType = *nullableType;
    resultType.removeFlag(TypeInfoFlagsE::Nullable);

    return sema.typeMgr().addType(resultType);
}

namespace
{
    bool callsNoReturnFunction(Sema& sema, AstNodeRef callRef)
    {
        const SemaNodeView view = sema.viewSymbol(callRef);
        if (!view.hasSymbol() || !view.sym()->isFunction())
            return false;

        return view.sym()->cast<SymbolFunction>().attributes().hasRtFlag(RtAttributeFlagsE::NoReturn);
    }

    bool stopsAtFunctionExit(Sema& sema, AstNodeRef nodeRef, const AstNode& node)
    {
        switch (node.id())
        {
            case AstNodeId::ReturnStmt:
            case AstNodeId::FailExpr:
            case AstNodeId::UnreachableStmt:
                return true;

            case AstNodeId::IntrinsicCallExpr:
                return node.cast<AstIntrinsicCallExpr>().intrinsicId == TokenId::IntrinsicPanic || callsNoReturnFunction(sema, nodeRef);

            case AstNodeId::CallExpr:
                return callsNoReturnFunction(sema, nodeRef);

            default:
                return false;
        }
    }

    struct ScopeExit
    {
        AstNodeRef scopeRef;
        ScopeExit* parent;
        AstNodeRef breakRef;
    };

    struct FlowTargets
    {
        AstNodeRef* breakRef       = nullptr;
        ScopeExit*  scopes         = nullptr;
        AstNodeRef* fallthroughRef = nullptr;
    };

    // Follow local continuation and record jumps at their destination. A return
    // later in a sequence cannot cover paths that jump past that sequence.
    class FunctionFlow
    {
    public:
        explicit FunctionFlow(Sema& sema) :
            sema_(sema)
        {
        }

        bool continues(AstNodeRef nodeRef, FlowTargets targets = {});
        AstNodeRef switchFallthrough(AstNodeRef switchRef, FlowTargets targets = {});
        AstNodeRef loopExitBreak(AstNodeRef bodyRef, ScopeExit* scopes = nullptr);
        AstNodeRef scopeExitBreak(AstNodeRef scopeRef, FlowTargets targets = {});

    private:
        Sema& sema_;

        bool continuesSequence(AstNodeRef nodeRef, SpanRef childrenRef, FlowTargets targets);
        bool continuesBranch(AstNodeRef conditionRef, AstNodeRef thenRef, AstNodeRef elseRef, FlowTargets targets);
        bool continuesLoop(AstNodeRef conditionRef, AstNodeRef bodyRef, FlowTargets targets);
        bool isFalseCondition(AstNodeRef conditionRef) const;
        bool caseTestAlwaysMatches(AstNodeRef caseRef, const AstSwitchCaseStmt& caseStmt, bool expressionless) const;
    };

    bool FunctionFlow::isFalseCondition(AstNodeRef conditionRef) const
    {
        return conditionRef.isValid() && sema_.viewConstant(conditionRef).cstRef() == sema_.cstMgr().cstFalse();
    }

    bool FunctionFlow::continuesSequence(AstNodeRef nodeRef, SpanRef childrenRef, FlowTargets targets)
    {
        if (!sema_.ast().hasSpan(childrenRef))
            return true;

        const auto children = sema_.ast().nodeSpan(childrenRef);
        for (auto chunk = children.chunksBegin(); chunk != children.chunksEnd(); ++chunk)
        {
            for (const AstNodeRef childRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                if (!sema_.isImplicitCodeBlockArg(nodeRef, childRef) && !continues(childRef, targets))
                    return false;
            }
        }

        return true;
    }

    bool FunctionFlow::continuesBranch(AstNodeRef conditionRef, AstNodeRef thenRef, AstNodeRef elseRef, FlowTargets targets)
    {
        if (conditionRef.isValid())
        {
            const SemaNodeView condition = sema_.viewConstant(conditionRef);
            if (condition.cst() && condition.cst()->isBool())
                return continues(condition.cst()->getBool() ? thenRef : elseRef, targets);
        }

        // Visit both branches even if the first one continues. Either can jump out of a scope.
        const bool thenContinues = continues(thenRef, targets);
        const bool elseContinues = continues(elseRef, targets);
        return thenContinues || elseContinues;
    }

    bool FunctionFlow::continuesLoop(AstNodeRef conditionRef, AstNodeRef bodyRef, FlowTargets targets)
    {
        const ConstantRef condition = conditionRef.isValid() ? sema_.viewConstant(conditionRef).cstRef() : sema_.cstMgr().cstTrue();
        if (condition == sema_.cstMgr().cstFalse())
            return true;

        const AstNodeRef breakRef = loopExitBreak(bodyRef, targets.scopes);
        return condition != sema_.cstMgr().cstTrue() || breakRef.isValid();
    }

    AstNodeRef FunctionFlow::loopExitBreak(AstNodeRef bodyRef, ScopeExit* scopes)
    {
        AstNodeRef breakRef;
        continues(bodyRef, {&breakRef, scopes});
        return breakRef;
    }

    AstNodeRef FunctionFlow::scopeExitBreak(AstNodeRef scopeRef, FlowTargets targets)
    {
        const auto& scope = sema_.node(scopeRef).cast<AstScopeStmt>();
        ScopeExit   exit{scopeRef, targets.scopes, {}};
        continues(scope.nodeBodyRef, {targets.breakRef, &exit});
        return exit.breakRef;
    }

    bool FunctionFlow::caseTestAlwaysMatches(AstNodeRef caseRef, const AstSwitchCaseStmt& caseStmt, bool expressionless) const
    {
        if (caseStmt.spanExprRef.isInvalid())
            return true;
        if (!expressionless)
            return false;
        if (caseStmt.conditionBindingRef(sema_.ast()).isValid())
        {
            const auto* lowering = sema_.loweringPayload<CodeGenLoweringPayload>(caseRef);
            return lowering && !lowering->conditionBindingTestsValue;
        }

        const auto conditions = sema_.ast().nodeSpan(caseStmt.spanExprRef);
        for (auto chunk = conditions.chunksBegin(); chunk != conditions.chunksEnd(); ++chunk)
        {
            for (const AstNodeRef conditionRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                if (sema_.viewConstant(conditionRef).cstRef() == sema_.cstMgr().cstTrue())
                    return true;
            }
        }
        return false;
    }

    AstNodeRef FunctionFlow::switchFallthrough(AstNodeRef switchRef, FlowTargets targets)
    {
        const auto& switchStmt = sema_.node(switchRef).cast<AstSwitchStmt>();
        AstNodeRef  witness;
        if (!SemaSwitch::alwaysMatchesACase(sema_, switchRef, switchStmt))
        {
            if (!targets.scopes)
                return switchRef;
            witness = switchRef;
        }

        const auto* payload         = sema_.semaPayload<SwitchPayload>(switchRef);
        const bool  dynamicDispatch = payload && SemaSwitch::usesDynamicDispatch(sema_, switchStmt, payload->exprTypeRef);

        bool       canTest = true;
        AstNodeRef fallthroughRef;
        AstNodeRef resumedTestRef;
        SmallVector<AstNodeRef> cases;
        sema_.ast().appendNodes(cases, switchStmt.spanChildrenRef);
        for (const AstNodeRef childRef : cases)
        {
            if ((witness.isValid() && !targets.scopes) || (!canTest && fallthroughRef.isInvalid()))
                break;

            const AstNodeRef caseRef = sema_.resolvedNodeRef(childRef);
            if (caseRef.isInvalid())
                continue;
            const auto* caseStmt = sema_.node(caseRef).safeCast<AstSwitchCaseStmt>();
            if (!caseStmt)
                continue;

            bool entersBody = fallthroughRef.isValid();
            if (entersBody && SemaSwitch::fallthroughTestsCase(sema_.ast(), *caseStmt, dynamicDispatch))
            {
                // This jump resumes the remaining case tests, even if an earlier
                // default already ended the original search.
                canTest        = true;
                resumedTestRef = fallthroughRef;
                entersBody     = false;
            }

            const ConstantRef guard = caseStmt->nodeWhereRef.isValid() ? sema_.viewConstant(caseStmt->nodeWhereRef).cstRef() : sema_.cstMgr().cstTrue();
            entersBody = entersBody || (canTest && guard != sema_.cstMgr().cstFalse());
            if (canTest && guard == sema_.cstMgr().cstTrue() && caseTestAlwaysMatches(caseRef, *caseStmt, switchStmt.nodeExprRef.isInvalid()))
            {
                canTest = false;
                resumedTestRef.setInvalid();
            }

            fallthroughRef.setInvalid();
            if (!entersBody)
                continue;

            AstNodeRef breakRef;
            const bool caseContinues = continues(caseStmt->nodeBodyRef, {&breakRef, targets.scopes, &fallthroughRef});
            if (witness.isInvalid() && (caseContinues || breakRef.isValid()))
                witness = caseRef;
        }
        return witness.isValid() ? witness : resumedTestRef;
    }

    bool FunctionFlow::continues(AstNodeRef nodeRef, FlowTargets targets)
    {
        if (nodeRef.isInvalid())
            return true;

        const AstNode& node = sema_.node(nodeRef);
        switch (node.id())
        {
            case AstNodeId::BreakStmt:
                if (targets.breakRef && targets.breakRef->isInvalid())
                    *targets.breakRef = nodeRef;
                return false;

            case AstNodeId::ScopedBreakStmt:
            {
                const auto* payload = sema_.semaPayload<ScopedBreakSemaPayload>(nodeRef);
                for (ScopeExit* scope = targets.scopes; payload && scope; scope = scope->parent)
                {
                    if (scope->scopeRef == payload->targetScopeRef)
                    {
                        if (scope->breakRef.isInvalid())
                            scope->breakRef = nodeRef;
                        break;
                    }
                }
                return false;
            }

            case AstNodeId::FallThroughStmt:
                if (targets.fallthroughRef && targets.fallthroughRef->isInvalid())
                    *targets.fallthroughRef = nodeRef;
                return false;

            case AstNodeId::ContinueStmt:
                return false;

            case AstNodeId::IfStmt:
            {
                const auto& branch = node.cast<AstIfStmt>();
                return continuesBranch(branch.nodeConditionRef, branch.nodeIfBlockRef, branch.nodeElseBlockRef, targets);
            }

            case AstNodeId::IfVarDecl:
            {
                const auto& branch = node.cast<AstIfVarDecl>();
                if (isFalseCondition(branch.nodeWhereRef))
                    return continues(branch.nodeElseBlockRef, targets);

                const auto* lowering = sema_.loweringPayload<CodeGenLoweringPayload>(nodeRef);
                const AstNodeRef conditionRef = lowering && !lowering->conditionBindingTestsValue ? branch.nodeWhereRef : AstNodeRef::invalid();
                return continuesBranch(conditionRef, branch.nodeIfBlockRef, branch.nodeElseBlockRef, targets);
            }

            case AstNodeId::CompilerIf:
            {
                const auto& branch = node.cast<AstCompilerIf>();
                const SemaNodeView condition = sema_.viewConstant(branch.nodeConditionRef);
                return !condition.cst() || continues(condition.cst()->getBool() ? branch.nodeIfBlockRef : branch.nodeElseBlockRef, targets);
            }

            case AstNodeId::CompilerSwitch:
                return continues(SemaSwitch::selectedCompilerSwitchBody(sema_, nodeRef), targets);

            case AstNodeId::CompilerFunc:
            case AstNodeId::CompilerShortFunc:
            case AstNodeId::CompilerInject:
            {
                // Generated statements run in the enclosing function. Ordinary
                // inline calls have their own return boundary.
                const AstNodeRef generatedRef = sema_.resolvedNodeRef(nodeRef);
                return generatedRef == nodeRef || continues(generatedRef, targets);
            }

            case AstNodeId::SwitchStmt:
                return switchFallthrough(nodeRef, targets).isValid();

            case AstNodeId::InfiniteLoopStmt:
                return continuesLoop({}, node.cast<AstInfiniteLoopStmt>().nodeBodyRef, targets);

            case AstNodeId::WhileStmt:
            {
                const auto& loop = node.cast<AstWhileStmt>();
                return continuesLoop(loop.nodeExprRef, loop.nodeBodyRef, targets);
            }

            case AstNodeId::ForCStyleStmt:
            {
                const auto& loop = node.cast<AstForCStyleStmt>();
                return continuesLoop(loop.nodeExprRef, loop.nodeBodyRef, targets);
            }

            case AstNodeId::ForStmt:
            {
                if (!targets.scopes)
                    return true;

                const auto&        loop  = node.cast<AstForStmt>();
                const SemaNodeView count = sema_.viewConstant(loop.nodeExprRef);
                const bool         empty = count.cst() && count.cst()->isInt() && count.cst()->getInt().isZero();
                if (!empty && !isFalseCondition(loop.nodeWhereRef))
                    loopExitBreak(loop.nodeBodyRef, targets.scopes);
                return true;
            }

            case AstNodeId::ForeachStmt:
            {
                const auto& loop = node.cast<AstForeachStmt>();
                if (targets.scopes && !isFalseCondition(loop.nodeWhereRef))
                    loopExitBreak(loop.nodeBodyRef, targets.scopes);
                return true;
            }

            case AstNodeId::AttributeList:
                return continues(node.cast<AstAttributeList>().nodeBodyRef, targets);

            case AstNodeId::TopLevelBlock:
                return continuesSequence(nodeRef, node.cast<AstTopLevelBlock>().spanChildrenRef, targets);

            case AstNodeId::EmbeddedBlock:
                return continuesSequence(nodeRef, node.cast<AstEmbeddedBlock>().spanChildrenRef, targets);

            case AstNodeId::FunctionBody:
                return continuesSequence(nodeRef, node.cast<AstFunctionBody>().spanChildrenRef, targets);

            case AstNodeId::SwitchCaseBody:
                return continuesSequence(nodeRef, node.cast<AstSwitchCaseBody>().spanChildrenRef, targets);

            case AstNodeId::ElseStmt:
                return continuesSequence(nodeRef, node.cast<AstElseStmt>().spanChildrenRef, targets);

            case AstNodeId::ElseIfStmt:
                return continuesSequence(nodeRef, node.cast<AstElseIfStmt>().spanChildrenRef, targets);

            case AstNodeId::ScopeStmt:
            {
                const auto& scope = node.cast<AstScopeStmt>();
                if (scope.tokNameRef.isInvalid())
                    return continues(scope.nodeBodyRef, targets);

                ScopeExit  exit{nodeRef, targets.scopes, {}};
                targets.scopes = &exit;
                const bool bodyContinues = continues(scope.nodeBodyRef, targets);
                return bodyContinues || exit.breakRef.isValid();
            }

            case AstNodeId::WithStmt:
                return continues(node.cast<AstWithStmt>().nodeBodyRef, targets);

            case AstNodeId::WithVarDecl:
                return continues(node.cast<AstWithVarDecl>().nodeBodyRef, targets);

            case AstNodeId::ErrorManagementStmt:
            {
                const auto& guard = node.cast<AstErrorManagementStmt>();
                continues(guard.nodeBodyRef, targets);
                continues(guard.nodeHandlerRef, targets);
                // The error path may resume after the statement.
                return true;
            }

            default:
                return !stopsAtFunctionExit(sema_, nodeRef, node);
        }
    }

    bool compoundStopsBlockFlow(Sema& sema, SpanRef childrenRef)
    {
        if (!sema.ast().hasSpan(childrenRef))
            return false;

        const size_t count = sema.ast().spanSize(childrenRef);
        return count && SemaHelpers::stopsLocalFlow(sema, sema.ast().nthNode(childrenRef, count - 1));
    }
}

AstNodeRef SemaHelpers::findLoopExitBreak(Sema& sema, AstNodeRef bodyRef)
{
    return FunctionFlow(sema).loopExitBreak(bodyRef);
}

AstNodeRef SemaHelpers::findScopeExitBreak(Sema& sema, AstNodeRef scopeRef)
{
    return FunctionFlow(sema).scopeExitBreak(scopeRef);
}

AstNodeRef SemaHelpers::findSwitchFallthrough(Sema& sema, AstNodeRef switchRef)
{
    return FunctionFlow(sema).switchFallthrough(switchRef);
}

bool SemaHelpers::stopsLocalFlow(Sema& sema, AstNodeRef nodeRef, LocalFlowStop stop)
{
    if (stop == LocalFlowStop::Function)
        return !FunctionFlow(sema).continues(nodeRef);

    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = sema.node(nodeRef);
    switch (node.id())
    {
        case AstNodeId::BreakStmt:
        case AstNodeId::ContinueStmt:
        case AstNodeId::FallThroughStmt:
            return true;

        case AstNodeId::IfStmt:
        {
            const auto& branch = node.cast<AstIfStmt>();
            return stopsLocalFlow(sema, branch.nodeIfBlockRef) && stopsLocalFlow(sema, branch.nodeElseBlockRef);
        }

        case AstNodeId::IfVarDecl:
        {
            const auto& branch = node.cast<AstIfVarDecl>();
            return stopsLocalFlow(sema, branch.nodeIfBlockRef) && stopsLocalFlow(sema, branch.nodeElseBlockRef);
        }

        case AstNodeId::SwitchStmt:
            return findSwitchFallthrough(sema, nodeRef).isInvalid();

        case AstNodeId::AttributeList:
            return stopsLocalFlow(sema, node.cast<AstAttributeList>().nodeBodyRef);

        case AstNodeId::EmbeddedBlock:
            return compoundStopsBlockFlow(sema, node.cast<AstEmbeddedBlock>().spanChildrenRef);

        case AstNodeId::FunctionBody:
            return compoundStopsBlockFlow(sema, node.cast<AstFunctionBody>().spanChildrenRef);

        case AstNodeId::SwitchCaseBody:
            return compoundStopsBlockFlow(sema, node.cast<AstSwitchCaseBody>().spanChildrenRef);

        case AstNodeId::ElseStmt:
            return compoundStopsBlockFlow(sema, node.cast<AstElseStmt>().spanChildrenRef);

        case AstNodeId::ElseIfStmt:
            return compoundStopsBlockFlow(sema, node.cast<AstElseIfStmt>().spanChildrenRef);

        case AstNodeId::ScopeStmt:
        {
            const auto& scope = node.cast<AstScopeStmt>();
            return scope.tokNameRef.isInvalid() && stopsLocalFlow(sema, scope.nodeBodyRef);
        }

        default:
            return stopsAtFunctionExit(sema, nodeRef, node);
    }
}

void SemaHelpers::addNarrowFacts(SemaFrame& frame, std::span<const SemaNarrowFact> facts)
{
    for (const SemaNarrowFact& fact : facts)
    {
        // Guard collection only ever produces proofs; kills go through addNarrowKill.
        SWC_ASSERT(fact.holds);
        if (fact.kind == SemaNarrowFactKind::Case)
            frame.addNarrowCaseFact({fact.path.data(), fact.path.size()}, fact.cases);
        else
            frame.addNarrowFact({fact.path.data(), fact.path.size()}, fact.kind);
    }
}

namespace
{
    void retainNarrowFactsForImmutableLocalRoots(SemaFrame& frame)
    {
        // An implicit member write may target `me` or a `with` subject, but it
        // cannot replace an unrelated local `let`. Facts about fields of that
        // local can still be invalidated through a `with` subject.
        SmallVector4<SemaNarrowFact> kept;
        for (const SemaNarrowFact& fact : frame.narrowFacts())
        {
            if (fact.path.size() != 1)
                continue;

            const Symbol* root = fact.path.front();
            if (root->isLetVariable() && root->cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
                kept.push_back(fact);
        }

        frame.clearNarrowFacts();
        for (const SemaNarrowFact& fact : kept)
        {
            const auto path = std::span<const Symbol* const>{fact.path.data(), fact.path.size()};
            if (!fact.holds)
                frame.addNarrowKill(path);
            else if (fact.kind == SemaNarrowFactKind::Case)
                frame.addNarrowCaseFact(path, fact.cases);
            else
                frame.addNarrowFact(path, fact.kind);
        }
    }

    // Find assignment/address-of roots before semantic resolution.
    void collectNarrowWrittenRoot(Sema& sema, AstNodeRef nodeRef, SmallVector8<IdentifierRef>& outRoots, bool& outImplicitMemberWrite)
    {
        while (nodeRef.isValid())
        {
            const AstNode& node = sema.node(nodeRef);
            switch (node.id())
            {
                case AstNodeId::ParenExpr:
                    nodeRef = node.cast<AstParenExpr>().nodeExprRef;
                    continue;

                case AstNodeId::MemberAccessExpr:
                    nodeRef = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                    continue;

                case AstNodeId::AutoMemberAccessExpr:
                    // Implicit `me`/`with` rooted write: cannot attribute it syntactically.
                    outImplicitMemberWrite = true;
                    return;

                case AstNodeId::Identifier:
                {
                    const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, node.codeRef());
                    if (idRef.isValid())
                        outRoots.push_back(idRef);

                    return;
                }

                default:
                    // Tracked paths never traverse indexing, so indexed writes cannot
                    // invalidate a tracked pointer path.
                    return;
            }
        }
    }

    void collectNarrowLoopBodyWrites(Sema& sema, AstNodeRef bodyRef, SmallVector8<IdentifierRef>& outRoots, bool& outKillAll, bool& outImplicitMemberWrite)
    {
        SmallVector<AstNodeRef> stack;
        stack.push_back(bodyRef);

        while (!stack.empty() && !outKillAll)
        {
            const AstNodeRef nodeRef = stack.back();
            stack.pop_back();

            if (nodeRef.isInvalid())
                continue;

            const AstNode& node = sema.node(nodeRef);
            switch (node.id())
            {
                case AstNodeId::AssignStmt:
                    // Compound assignments (`+=`, ...) cannot make a pointer null.
                    if (sema.token(node.codeRef()).id == TokenId::SymEqual)
                        collectNarrowWrittenRoot(sema, node.cast<AstAssignStmt>().nodeLeftRef, outRoots, outImplicitMemberWrite);
                    break;

                case AstNodeId::AssignList:
                    // Declaration patterns bind fresh locals and do not overwrite an outer path.
                    if (!node.cast<AstAssignList>().hasFlag(AstAssignListFlagsE::DeclarationPattern))
                        outKillAll = true;
                    break;

                case AstNodeId::UnaryExpr:
                    if (sema.token(node.codeRef()).id == TokenId::SymAmpersand)
                        collectNarrowWrittenRoot(sema, node.cast<AstUnaryExpr>().nodeExprRef, outRoots, outImplicitMemberWrite);
                    break;

                default:
                    break;
            }

            node.collectChildrenFromAst(stack, sema.ast());
        }
    }
}

void SemaHelpers::killNarrowFactsForLoopBody(Sema& sema, AstNodeRef bodyRef, SemaFrame& frame)
{
    if (!frame.hasNarrowFacts())
        return;

    // A loop body executes multiple times: any fact whose root the body may reassign (or
    // whose address it takes) is not stable across the back edge, so drop it up front.
    SmallVector8<IdentifierRef> writtenRoots;
    bool                        killAll             = false;
    bool                        implicitMemberWrite = false;
    collectNarrowLoopBodyWrites(sema, bodyRef, writtenRoots, killAll, implicitMemberWrite);

    if (killAll)
    {
        frame.clearNarrowFacts();
        return;
    }

    if (implicitMemberWrite)
        retainNarrowFactsForImmutableLocalRoots(frame);

    if (!writtenRoots.empty())
        frame.killNarrowFactsByRootId({writtenRoots.data(), writtenRoots.size()});
}

void SemaHelpers::killNarrowPathAfterStatement(Sema& sema, AstNodeRef exprRef, bool nonNull)
{
    // Kills matter only while facts are live. Search every frame because an
    // enclosing region may hold the proof even when the top frame has none.
    if (!nonNull && !sema.anyFrameHasNarrowFacts())
        return;

    SmallVector4<const Symbol*> path;
    if (!extractNarrowPath(sema, exprRef, path))
        return;

    // Mutate live frames in place: pushing a frame with an ancestor-anchored pop from the
    // middle of a statement would break the LIFO discipline of the deferred pops.
    if (nonNull)
    {
        // Only a nullable-declared path can carry a proof; a bare one is never narrowed.
        if (!typeRefIsNullable(sema, path.back()->typeRef()))
            return;

        // A positive fact only holds inside the current region, which is the statement's frame:
        // the binding frames above it are scoped to one operand, not to the flow.
        sema.addNarrowFactPastBindingFrames({path.data(), path.size()}, SemaNarrowFactKind::NonNull);
    }
    else
    {
        // Invalidate every region proving this path or a descendant. A plain
        // struct prefix still matters: aliasing it lets a callee rewrite its
        // nullable fields, so the prefix itself need not be nullable.
        sema.addNarrowKillAllFrames({path.data(), path.size()});
    }
}

void SemaHelpers::preferContextualAutoMemberBindingType(Sema& sema, AstNodeRef exprRef)
{
    AstNodeRef targetRef = resolveTransparentConditionExprSourceRef(sema, exprRef);
    if (targetRef.isInvalid())
        targetRef = exprRef;
    if (targetRef.isInvalid())
        return;

    AstNode& targetNode = sema.node(targetRef);
    if (targetNode.is(AstNodeId::AutoMemberAccessExpr))
        targetNode.cast<AstAutoMemberAccessExpr>().addFlag(AstAutoMemberAccessExprFlagsE::PreferBindingType);
}

SWC_END_NAMESPACE();
