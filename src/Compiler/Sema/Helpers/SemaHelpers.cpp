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
                // 'expr[as T]' shares the cast node but is a dereference, not a conversion: its
                // operand is the pointer, not the value. Looking through it reports the pointer as
                // the expression's source, which makes a receiver's address stop travelling into
                // the 'me' parameter of a method or operator call on the opened place.
                if (node.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::DerefPlace))
                    return AstNodeRef::invalid();
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

}

TypeRef SemaHelpers::unwrapBindingType(TaskContext& ctx, TypeRef typeRef)
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

bool SemaHelpers::bindingSymbolResolvesStandalone(Sema& sema, const SymbolVariable& symVar)
{
    if (symVar.hasGlobalStorage())
        return true;

    // An instance field only exists relative to a base expression.
    if (symVar.ownerSymMap() && symVar.ownerSymMap()->isStruct())
        return false;

    // A parameter resolves positionally in the function whose body is being analyzed.
    // Another function's parameter - a macro receiver bound at the call site - has no
    // storage there, and codegen would remap it by name onto an unrelated caller
    // parameter.
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        const SymbolFunction* fn = sema.currentFunction();
        if (!fn)
            return false;
        const auto& params = fn->parameters();
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

namespace
{
    // Resolve substitutes and unwrap transparent wrappers (parens, casts) down to the
    // expression that actually carries the narrowing information.
    AstNodeRef resolveNarrowSourceRef(Sema& sema, AstNodeRef nodeRef)
    {
        for (int depth = 0; depth < 16 && nodeRef.isValid(); depth++)
        {
            const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
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

    const TypeInfo& narrowUnwrappedType(Sema& sema, TypeRef typeRef)
    {
        TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (unwrappedTypeRef.isInvalid())
            unwrappedTypeRef = typeRef;

        return sema.typeMgr().get(unwrappedTypeRef);
    }

    bool typeRefIsNullable(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        return narrowUnwrappedType(sema, typeRef).isNullable();
    }

    // A fact only attaches to a path whose declared type can carry it.
    bool narrowTypeAcceptsKind(Sema& sema, TypeRef typeRef, SemaNarrowFactKind kind)
    {
        if (!typeRef.isValid())
            return false;

        switch (kind)
        {
            case SemaNarrowFactKind::NonNull:
                return narrowUnwrappedType(sema, typeRef).isNullable();
            case SemaNarrowFactKind::NonZero:
                return narrowUnwrappedType(sema, typeRef).isIntLike();
        }

        return false;
    }

    bool isNarrowRootVariable(const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::GlobalStorage) ||
            symVar.hasGlobalStorage() ||
            symVar.isClosureCapture())
            return false;

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

        // Check the DECLARED type of the path's last component: by the time guards are
        // collected, the condition expression node itself may already have been cast to
        // bool by the truthiness check.
        if (!narrowTypeAcceptsKind(sema, path.back()->typeRef(), kind))
            return;

        appendNarrowFact(facts, path, kind);
    }

    // `x != <sentinel>` proves the fact on the true edge, `x == <sentinel>` on the false
    // one. Returns false when the comparison is not against this kind's sentinel, so the
    // caller can try the next kind.
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

    // Unwrap substitutes and transparent wrappers (parens, casts): they do not change
    // which storage path is being accessed.
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

    // Leaf: a resolved variable usable as a narrowing root.
    const SemaNodeView view = sema.view(resolvedRef, SemaNodeViewPartE::Symbol);
    const Symbol*      sym  = view.singleSymbol();
    if (!sym || !sym->isVariable())
        return false;
    if (!isNarrowRootVariable(sym->cast<SymbolVariable>()))
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
            if (sema.token(unary.codeRef()).id != TokenId::SymBang)
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
                // `a and b` true ⇒ both sides true.
                for (auto& fact : left.whenTrue)
                    out.whenTrue.push_back(std::move(fact));
                for (auto& fact : right.whenTrue)
                    out.whenTrue.push_back(std::move(fact));
            }
            else if (op == TokenId::KwdOr)
            {
                // `a or b` false ⇒ both sides false.
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

            if (collectSentinelComparisonGuard(sema, relational, op, SemaNarrowFactKind::NonNull, out))
                return;
            collectSentinelComparisonGuard(sema, relational, op, SemaNarrowFactKind::NonZero, out);
            return;
        }

        default:
            // Bare truthiness. Only the non-null reading is inferred here: `if count` is a
            // very common shape, and recording a fact no consumer reads would slow every
            // narrowing query down for nothing. A non-zero proof must be spelled `!= 0`.
            collectNarrowGuardFromExpr(sema, resolvedRef, SemaNarrowFactKind::NonNull, out.whenTrue);
    }
}

TypeRef SemaHelpers::nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
{
    if (!typeRef.isValid() || !sema.frame().hasNarrowFacts())
        return TypeRef::invalid();

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
                const AstNodeRef leftRef = sema.viewZero(assign.nodeLeftRef).nodeRef();
                if (leftRef == nodeRef)
                    return TypeRef::invalid();

                // Multi-assign: each individual target of the list keeps its declared type.
                if (leftRef.isValid() && sema.node(leftRef).is(AstNodeId::AssignList))
                {
                    SmallVector<AstNodeRef> targets;
                    sema.node(leftRef).collectChildrenFromAst(targets, sema.ast());
                    for (const AstNodeRef targetRef : targets)
                    {
                        if (sema.viewZero(targetRef).nodeRef() == nodeRef)
                            return TypeRef::invalid();
                    }
                }
            }
        }
    }

    // Prefer stripping the Nullable flag from the type IN PLACE so the narrowed type
    // keeps its exact structure (alias identity included); unwrap aliases only to find
    // a flag hidden behind them.
    TypeRef  nullableTypeRef = typeRef;
    TypeInfo nullableType    = sema.typeMgr().get(typeRef);
    if (!nullableType.isNullable())
    {
        nullableTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (nullableTypeRef.isInvalid())
            return TypeRef::invalid();
        nullableType = sema.typeMgr().get(nullableTypeRef);
        if (!nullableType.isNullable())
            return TypeRef::invalid();
    }

    SmallVector4<const Symbol*> path;
    if (!extractNarrowPath(sema, nodeRef, path))
        return TypeRef::invalid();

    if (!sema.frame().queryNarrowFact({path.data(), path.size()}, SemaNarrowFactKind::NonNull))
        return TypeRef::invalid();

    TypeInfo resultType = nullableType;
    resultType.removeFlag(TypeInfoFlagsE::Nullable);
    return sema.typeMgr().addType(resultType);
}

bool SemaHelpers::stopsLocalFlow(Sema& sema, AstNodeRef nodeRef, LocalFlowStop stop)
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = sema.node(nodeRef);
    switch (node.id())
    {
        case AstNodeId::ReturnStmt:
        case AstNodeId::BreakStmt:
        case AstNodeId::ContinueStmt:
        case AstNodeId::FallThroughStmt:
        case AstNodeId::FailExpr:
            return true;

        case AstNodeId::UnreachableStmt:
            return stop == LocalFlowStop::Declared;

        case AstNodeId::IntrinsicCallExpr:
            return stop == LocalFlowStop::Declared && sema.token(node.codeRef()).id == TokenId::IntrinsicPanic;

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

        case AstNodeId::EmbeddedBlock:
        case AstNodeId::FunctionBody:
        case AstNodeId::SwitchCaseBody:
        case AstNodeId::ElseStmt:
        case AstNodeId::ElseIfStmt:
        {
            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, sema.ast());
            if (children.empty())
                return false;
            return stopsLocalFlow(sema, children.back(), stop);
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
        frame.addNarrowFact({fact.path.data(), fact.path.size()}, fact.kind);
    }
}

namespace
{
    // Walk an assignment (or address-of) target down to its leftmost root identifier,
    // without requiring the subtree to be sema'd. Returns the collected root identifier,
    // or sets `outKillAll` when the write cannot be attributed to a single root.
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
                    // Index writes (`a[i] = ...`) and other shapes never re-null a tracked
                    // pointer path (paths never traverse an indexing), so ignore them.
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
                    // Multi-assign / destructuring: give up on attribution.
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
    // Adding a positive fact is only useful when narrowing is possible at all; killing is
    // only needed when something is currently narrowed.
    if (!nonNull && !sema.frame().hasNarrowFacts())
        return;

    SmallVector4<const Symbol*> path;
    if (!extractNarrowPath(sema, exprRef, path))
        return;

    // Only nullable-declared paths participate in narrowing.
    if (!typeRefIsNullable(sema, path.back()->typeRef()))
        return;

    // Mutate live frames in place: pushing a frame with an ancestor-anchored pop from the
    // middle of a statement would break the LIFO discipline of the deferred pops.
    if (nonNull)
    {
        // A positive fact only holds inside the current region: add it to the top frame.
        sema.frame().addNarrowFact({path.data(), path.size()}, SemaNarrowFactKind::NonNull);
    }
    else
    {
        // A kill must outlive any enclosing region that proved the path non-null.
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
