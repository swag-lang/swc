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

namespace
{
    // Resolve substitutes and unwrap transparent wrappers (parens, casts) down to the
    // expression that actually carries the narrowing information.
    AstNodeRef resolveNullNarrowSourceRef(Sema& sema, AstNodeRef nodeRef)
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

    bool typeRefIsNullable(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (unwrappedTypeRef.isInvalid())
            unwrappedTypeRef = typeRef;

        return sema.typeMgr().get(unwrappedTypeRef).isNullable();
    }

    bool isNullNarrowRootVariable(const SymbolVariable& symVar)
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

    bool nullNarrowOperandIsNullLiteral(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = resolveNullNarrowSourceRef(sema, nodeRef);
        if (!resolvedRef.isValid())
            return false;

        if (sema.node(resolvedRef).is(AstNodeId::NullLiteral))
            return true;

        const SemaNodeView view = sema.view(resolvedRef, SemaNodeViewPartE::Type);
        return view.typeRef().isValid() && view.type()->isNull();
    }

    void appendNullNarrowFact(SmallVector2<SemaNullNarrowFact>& facts, SmallVector4<const Symbol*>& path)
    {
        auto& fact = facts.emplace_back();
        fact.path.assign(path.begin(), path.end());
        fact.nonNull = true;
    }

    void collectNullNarrowGuardFromExpr(Sema& sema, AstNodeRef exprRef, SmallVector2<SemaNullNarrowFact>& facts)
    {
        const AstNodeRef resolvedRef = resolveNullNarrowSourceRef(sema, exprRef);
        if (!resolvedRef.isValid())
            return;

        SmallVector4<const Symbol*> path;
        if (!SemaHelpers::extractNullNarrowPath(sema, resolvedRef, path))
            return;

        // Check the DECLARED type of the path's last component: by the time guards are
        // collected, the condition expression node itself may already have been cast to
        // bool by the truthiness check.
        if (!typeRefIsNullable(sema, path.back()->typeRef()))
            return;

        appendNullNarrowFact(facts, path);
    }
}

bool SemaHelpers::extractNullNarrowPath(Sema& sema, AstNodeRef nodeRef, SmallVector4<const Symbol*>& outPath)
{
    if (nodeRef.isInvalid())
        return false;

    // Unwrap substitutes and transparent wrappers (parens, casts): they do not change
    // which storage path is being accessed.
    const AstNodeRef resolvedRef = resolveNullNarrowSourceRef(sema, nodeRef);
    if (!resolvedRef.isValid())
        return false;

    const AstNode& node = sema.node(resolvedRef);
    if (node.is(AstNodeId::ParenExpr))
        return extractNullNarrowPath(sema, node.cast<AstParenExpr>().nodeExprRef, outPath);

    if (node.is(AstNodeId::MemberAccessExpr))
    {
        const auto& member = node.cast<AstMemberAccessExpr>();
        if (!extractNullNarrowPath(sema, member.nodeLeftRef, outPath))
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
    if (!isNullNarrowRootVariable(sym->cast<SymbolVariable>()))
        return false;

    outPath.push_back(sym);
    return true;
}

void SemaHelpers::collectNullNarrowGuards(Sema& sema, AstNodeRef condRef, NullNarrowGuards& out)
{
    const AstNodeRef resolvedRef = resolveNullNarrowSourceRef(sema, condRef);
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

            NullNarrowGuards child;
            collectNullNarrowGuards(sema, unary.nodeExprRef, child);
            for (auto& fact : child.whenTrue)
                out.whenFalse.push_back(std::move(fact));
            for (auto& fact : child.whenFalse)
                out.whenTrue.push_back(std::move(fact));
            return;
        }

        case AstNodeId::LogicalExpr:
        {
            const auto&      logical = node.cast<AstLogicalExpr>();
            NullNarrowGuards left;
            NullNarrowGuards right;
            collectNullNarrowGuards(sema, logical.nodeLeftRef, left);
            collectNullNarrowGuards(sema, logical.nodeRightRef, right);

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

            const bool leftIsNull  = nullNarrowOperandIsNullLiteral(sema, relational.nodeLeftRef);
            const bool rightIsNull = nullNarrowOperandIsNullLiteral(sema, relational.nodeRightRef);
            if (leftIsNull == rightIsNull)
                return;

            const AstNodeRef targetRef = leftIsNull ? relational.nodeRightRef : relational.nodeLeftRef;
            collectNullNarrowGuardFromExpr(sema, targetRef, op == TokenId::SymBangEqual ? out.whenTrue : out.whenFalse);
            return;
        }

        default:
            collectNullNarrowGuardFromExpr(sema, resolvedRef, out.whenTrue);
            return;
    }
}

TypeRef SemaHelpers::nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
{
    if (!typeRef.isValid() || !sema.frame().hasNullNarrowFacts())
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

    TypeRef nullableTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
    if (nullableTypeRef.isInvalid())
        nullableTypeRef = typeRef;

    const TypeInfo& nullableType = sema.typeMgr().get(nullableTypeRef);
    if (!nullableType.isNullable())
        return TypeRef::invalid();

    SmallVector4<const Symbol*> path;
    if (!extractNullNarrowPath(sema, nodeRef, path))
        return TypeRef::invalid();

    if (!sema.frame().queryNullNarrowNonNull({path.data(), path.size()}))
        return TypeRef::invalid();

    TypeInfo resultType = nullableType;
    resultType.removeFlag(TypeInfoFlagsE::Nullable);
    return sema.typeMgr().addType(resultType);
}

bool SemaHelpers::nullNarrowStopsLocalFlow(Sema& sema, AstNodeRef nodeRef)
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
        case AstNodeId::UnreachableStmt:
        case AstNodeId::ThrowExpr:
            return true;

        case AstNodeId::IntrinsicCallExpr:
            return sema.token(node.codeRef()).id == TokenId::IntrinsicPanic;

        case AstNodeId::IfStmt:
        {
            const auto& ifStmt = node.cast<AstIfStmt>();
            return ifStmt.nodeElseBlockRef.isValid() && nullNarrowStopsLocalFlow(sema, ifStmt.nodeIfBlockRef) && nullNarrowStopsLocalFlow(sema, ifStmt.nodeElseBlockRef);
        }

        case AstNodeId::IfVarDecl:
        {
            const auto& ifVarDecl = node.cast<AstIfVarDecl>();
            return ifVarDecl.nodeElseBlockRef.isValid() && nullNarrowStopsLocalFlow(sema, ifVarDecl.nodeIfBlockRef) && nullNarrowStopsLocalFlow(sema, ifVarDecl.nodeElseBlockRef);
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
            return nullNarrowStopsLocalFlow(sema, children.back());
        }

        default:
            return false;
    }
}

void SemaHelpers::addNullNarrowFacts(SemaFrame& frame, std::span<const SemaNullNarrowFact> facts)
{
    for (const SemaNullNarrowFact& fact : facts)
        frame.addNullNarrowFact({fact.path.data(), fact.path.size()}, fact.nonNull);
}

namespace
{
    // Walk an assignment (or address-of) target down to its leftmost root identifier,
    // without requiring the subtree to be sema'd. Returns the collected root identifier,
    // or sets `outKillAll` when the write cannot be attributed to a single root.
    void collectNullNarrowWrittenRoot(Sema& sema, AstNodeRef nodeRef, SmallVector8<IdentifierRef>& outRoots, bool& outKillAll)
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

    void collectNullNarrowLoopBodyWrites(Sema& sema, AstNodeRef bodyRef, SmallVector8<IdentifierRef>& outRoots, bool& outKillAll)
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
                        collectNullNarrowWrittenRoot(sema, node.cast<AstAssignStmt>().nodeLeftRef, outRoots, outKillAll);
                    break;

                case AstNodeId::AssignList:
                    // Multi-assign / destructuring: give up on attribution.
                    outKillAll = true;
                    break;

                case AstNodeId::UnaryExpr:
                    if (sema.token(node.codeRef()).id == TokenId::SymAmpersand)
                        collectNullNarrowWrittenRoot(sema, node.cast<AstUnaryExpr>().nodeExprRef, outRoots, outKillAll);
                    break;

                default:
                    break;
            }

            node.collectChildrenFromAst(stack, sema.ast());
        }
    }
}

void SemaHelpers::killNullNarrowFactsForLoopBody(Sema& sema, AstNodeRef bodyRef, SemaFrame& frame)
{
    if (!frame.hasNullNarrowFacts())
        return;

    // A loop body executes multiple times: any fact whose root the body may reassign (or
    // whose address it takes) is not stable across the back edge, so drop it up front.
    SmallVector8<IdentifierRef> writtenRoots;
    bool                        killAll = false;
    collectNullNarrowLoopBodyWrites(sema, bodyRef, writtenRoots, killAll);

    if (killAll)
    {
        frame.clearNullNarrowFacts();
        return;
    }

    if (!writtenRoots.empty())
        frame.killNullNarrowFactsByRootId({writtenRoots.data(), writtenRoots.size()});
}

void SemaHelpers::killNullNarrowPathAfterStatement(Sema& sema, AstNodeRef exprRef, bool nonNull)
{
    // Adding a positive fact is only useful when narrowing is possible at all; killing is
    // only needed when something is currently narrowed.
    if (!nonNull && !sema.frame().hasNullNarrowFacts())
        return;

    SmallVector4<const Symbol*> path;
    if (!extractNullNarrowPath(sema, exprRef, path))
        return;

    // Only nullable-declared paths participate in narrowing.
    if (!typeRefIsNullable(sema, path.back()->typeRef()))
        return;

    // Mutate live frames in place: pushing a frame with an ancestor-anchored pop from the
    // middle of a statement would break the LIFO discipline of the deferred pops.
    if (nonNull)
    {
        // A positive fact only holds inside the current region: add it to the top frame.
        sema.frame().addNullNarrowFact({path.data(), path.size()}, true);
    }
    else
    {
        // A kill must outlive any enclosing region that proved the path non-null.
        sema.addNullNarrowKillAllFrames({path.data(), path.size()});
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
