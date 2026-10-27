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
        // Dynamic conversions can produce null from a present box containing a null pointer.
        if (node.is(AstNodeId::CastExpr) && (node.cast<AstCastExpr>().modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}) || node.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::Fallible)))
            return AstNodeRef::invalid();
        if (node.is(AstNodeId::AutoCastExpr) && node.cast<AstAutoCastExpr>().modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}))
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

TypeRef SemaHelpers::nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
{
    if (!typeRef.isValid() || !sema.frame().hasNarrowFacts())
        return TypeRef::invalid();

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
    // Count only breaks leaving this loop. Nested loops/switches own their
    // breaks, and labelled exits need scope resolution this walk does not have.
    // Ignoring uncertain exits can miss a diagnostic; counting one can reject valid code.
    bool loopBodyBreaksOut(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        switch (node.id())
        {
            case AstNodeId::BreakStmt:
                return true;

            case AstNodeId::WhileStmt:
            case AstNodeId::ForeachStmt:
            case AstNodeId::ForCStyleStmt:
            case AstNodeId::ForStmt:
            case AstNodeId::InfiniteLoopStmt:
            case AstNodeId::SwitchStmt:
            case AstNodeId::FunctionDecl:
            case AstNodeId::FunctionExpr:
            case AstNodeId::ClosureExpr:
                return false;

            default:
                break;
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());

        return std::ranges::any_of(children, [&](AstNodeRef childRef) { return loopBodyBreaksOut(sema, childRef); });
    }

    bool compoundStopsLocalFlow(Sema& sema, SpanRef childrenRef, SemaHelpers::LocalFlowStop stop)
    {
        if (!sema.ast().hasSpan(childrenRef))
            return false;

        const auto children = sema.ast().nodeSpan(childrenRef);
        if (!children.size())
            return false;

        // Block checks need only the final statement; function checks accept any exit.
        if (stop != SemaHelpers::LocalFlowStop::Function)
            return SemaHelpers::stopsLocalFlow(sema, sema.ast().nthNode(childrenRef, children.size() - 1), stop);

        for (auto chunk = children.chunksBegin(); chunk != children.chunksEnd(); ++chunk)
        {
            for (const AstNodeRef childRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                if (SemaHelpers::stopsLocalFlow(sema, childRef, stop))
                    return true;
            }
        }

        return false;
    }

    bool endsWithFallthrough(Sema& sema, AstNodeRef bodyRef)
    {
        if (bodyRef.isInvalid())
            return false;

        const auto&  body  = sema.node(bodyRef).cast<AstSwitchCaseBody>();
        const size_t count = sema.ast().spanSize(body.spanChildrenRef);
        if (!count)
            return false;

        const AstNodeRef lastRef = sema.ast().nthNode(body.spanChildrenRef, count - 1);
        return lastRef.isValid() && sema.node(lastRef).is(AstNodeId::FallThroughStmt);
    }

    bool callsNoReturnFunction(Sema& sema, AstNodeRef callRef)
    {
        const SemaNodeView view = sema.viewSymbol(callRef);
        if (!view.hasSymbol() || !view.sym()->isFunction())
            return false;

        return view.sym()->cast<SymbolFunction>().attributes().hasRtFlag(RtAttributeFlagsE::NoReturn);
    }

    // Every case must leave, and some case must always match. For enums,
    // #complete supplies that guarantee even when its runtime range guard is off.
    bool switchStopsFunctionFlow(Sema& sema, AstNodeRef switchRef, const AstNode& node)
    {
        const auto& switchStmt = node.cast<AstSwitchStmt>();
        if (!SemaSwitch::alwaysMatchesACase(sema, switchRef, switchStmt))
            return false;

        SmallVector<AstNodeRef> caseBodies;
        sema.ast().appendNodes(caseBodies, switchStmt.spanChildrenRef);

        size_t count = 0;
        for (const AstNodeRef childRef : caseBodies)
        {
            if (childRef.isValid() && sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
                caseBodies[count++] = sema.node(childRef).cast<AstSwitchCaseStmt>().nodeBodyRef;
        }

        caseBodies.resize(count);

        for (uint32_t i = 0; i < caseBodies.size32(); i++)
        {
            if (SemaHelpers::stopsLocalFlow(sema, caseBodies[i], SemaHelpers::LocalFlowStop::Function))
                continue;

            // Fallthrough reaches the next case, which is checked separately.
            // The parser already prevents fallthrough past the final case.
            if (i + 1 < caseBodies.size32() && endsWithFallthrough(sema, caseBodies[i]))
                continue;

            return false;
        }

        return !caseBodies.empty();
    }
}

bool SemaHelpers::stopsLocalFlow(Sema& sema, AstNodeRef nodeRef, LocalFlowStop stop)
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = sema.node(nodeRef);
    switch (node.id())
    {
        case AstNodeId::ReturnStmt:
        case AstNodeId::FailExpr:
            return true;

        case AstNodeId::BreakStmt:
        case AstNodeId::ContinueStmt:
        case AstNodeId::FallThroughStmt:
            return stop != LocalFlowStop::Function;

        case AstNodeId::UnreachableStmt:
            return true;

        case AstNodeId::IntrinsicCallExpr:
            if (node.cast<AstIntrinsicCallExpr>().intrinsicId == TokenId::IntrinsicPanic)
                return true;

            return callsNoReturnFunction(sema, nodeRef);

        case AstNodeId::CallExpr:
            return callsNoReturnFunction(sema, nodeRef);

        case AstNodeId::IfStmt:
        {
            const auto& ifStmt = node.cast<AstIfStmt>();
            return ifStmt.nodeElseBlockRef.isValid() && stopsLocalFlow(sema, ifStmt.nodeIfBlockRef, stop) && stopsLocalFlow(sema, ifStmt.nodeElseBlockRef, stop);
        }

        case AstNodeId::IfVarDecl:
        {
            const auto& ifVarDecl = node.cast<AstIfVarDecl>();
            return ifVarDecl.nodeElseBlockRef.isValid() && stopsLocalFlow(sema, ifVarDecl.nodeIfBlockRef, stop) && stopsLocalFlow(sema, ifVarDecl.nodeElseBlockRef, stop);
        }

        // A case break leaves the switch, so test case bodies for function exits.
        case AstNodeId::SwitchStmt:
            return switchStopsFunctionFlow(sema, nodeRef, node);

        case AstNodeId::InfiniteLoopStmt:
            return stop == LocalFlowStop::Function && !loopBodyBreaksOut(sema, node.cast<AstInfiniteLoopStmt>().nodeBodyRef);

        case AstNodeId::WhileStmt:
        {
            if (stop != LocalFlowStop::Function)
                return false;

            const auto& whileStmt = node.cast<AstWhileStmt>();
            if (sema.viewConstant(whileStmt.nodeExprRef).cstRef() != sema.cstMgr().cstTrue())
                return false;

            return !loopBodyBreaksOut(sema, whileStmt.nodeBodyRef);
        }

        case AstNodeId::EmbeddedBlock:
            return compoundStopsLocalFlow(sema, node.cast<AstEmbeddedBlock>().spanChildrenRef, stop);

        case AstNodeId::FunctionBody:
            return compoundStopsLocalFlow(sema, node.cast<AstFunctionBody>().spanChildrenRef, stop);

        case AstNodeId::SwitchCaseBody:
            return compoundStopsLocalFlow(sema, node.cast<AstSwitchCaseBody>().spanChildrenRef, stop);

        case AstNodeId::ElseStmt:
            return compoundStopsLocalFlow(sema, node.cast<AstElseStmt>().spanChildrenRef, stop);

        case AstNodeId::ElseIfStmt:
            return compoundStopsLocalFlow(sema, node.cast<AstElseIfStmt>().spanChildrenRef, stop);

        // Only a named scope can be left by 'break to', so an unnamed one is just its body.
        case AstNodeId::ScopeStmt:
        {
            const auto& scopeStmt = node.cast<AstScopeStmt>();
            if (scopeStmt.tokNameRef.isInvalid())
                return stopsLocalFlow(sema, scopeStmt.nodeBodyRef, stop);
            if (stop != LocalFlowStop::Function)
                return false;
            return stopsLocalFlow(sema, scopeStmt.nodeBodyRef, stop);
        }

        // These statements contain bodies but are not block-level jumps.
        // Inspect them only for function exits, avoiding false unreachable reports.
        case AstNodeId::WithStmt:
        case AstNodeId::CompilerIf:
        case AstNodeId::CompilerSwitch:
        case AstNodeId::CompilerSwitchCase:
        {
            if (stop != LocalFlowStop::Function)
                return false;

            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, sema.ast());

            return std::ranges::any_of(children, [&](AstNodeRef childRef) { return stopsLocalFlow(sema, childRef, stop); });
        }

        default:
            return false;
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
    // Find assignment/address-of roots before semantic resolution. Set outKillAll
    // when syntax cannot identify one root.
    void collectNarrowWrittenRoot(Sema& sema, AstNodeRef nodeRef, SmallVector8<IdentifierRef>& outRoots, bool& outKillAll)
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
                    outKillAll = true;
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

    void collectNarrowLoopBodyWrites(Sema& sema, AstNodeRef bodyRef, SmallVector8<IdentifierRef>& outRoots, bool& outKillAll)
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
                        collectNarrowWrittenRoot(sema, node.cast<AstAssignStmt>().nodeLeftRef, outRoots, outKillAll);
                    break;

                case AstNodeId::AssignList:
                    // Declaration patterns bind fresh locals and do not overwrite an outer path.
                    if (!node.cast<AstAssignList>().hasFlag(AstAssignListFlagsE::DeclarationPattern))
                        outKillAll = true;
                    break;

                case AstNodeId::UnaryExpr:
                    if (sema.token(node.codeRef()).id == TokenId::SymAmpersand)
                        collectNarrowWrittenRoot(sema, node.cast<AstUnaryExpr>().nodeExprRef, outRoots, outKillAll);
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
    bool                        killAll = false;
    collectNarrowLoopBodyWrites(sema, bodyRef, writtenRoots, killAll);

    if (killAll)
    {
        frame.clearNarrowFacts();
        return;
    }

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
