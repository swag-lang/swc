#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef enumTypeRefFromSwitchType(Sema& sema, TypeRef switchTypeRef)
    {
        if (switchTypeRef.isInvalid())
            return TypeRef::invalid();

        // Follow aliases, but do NOT unwrap enums to their underlying integer type.
        // We need the enum type itself to provide a scope for `case Value` / `case .Value`.
        TypeRef result = switchTypeRef;
        while (true)
        {
            const TypeInfo& type = sema.typeMgr().get(result);
            if (!type.isAlias())
                break;
            const TypeRef next = type.underlyingTypeRef();
            if (next.isInvalid())
                break;
            result = next;
        }

        if (sema.typeMgr().get(result).isEnum())
            return result;
        return TypeRef::invalid();
    }
}

Result AstSwitchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    // Each case has its own breakable frame.
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        SemaFrame frame = sema.frame();
        frame.setBreakable(sema.curNodeRef(), SemaFrame::BreakableKind::Switch);
        frame.setCurrentSwitch(sema.curNodeRef());

        // If the switch expression is an enum (or an alias to an enum), provide the enum type
        // as a binding type so `case .EnumValue` can resolve via auto-scope.
        if (const TypeRef enumTypeRef = enumTypeRefFromSwitchType(sema, sema.typeRefOf(sema.curNodeRef())); enumTypeRef.isValid())
            frame.pushBindingType(enumTypeRef);

        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstSwitchStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView exprView(sema, nodeExprRef);

        const auto&     typeMgr   = sema.ctx().typeMgr();
        const TypeInfo& type      = typeMgr.get(exprView.typeRef);
        const TypeRef   ultimate  = type.expand(sema.ctx(), exprView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& finalType = typeMgr.get(ultimate);
        if (!finalType.isIntLike() && !finalType.isFloat() && !finalType.isBool() && !finalType.isString())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, nodeExprRef);

        sema.setType(sema.curNodeRef(), exprView.typeRef);
    }

    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNodeChild(Sema& sema, AstNodeRef& childRef) const
{
    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const TypeRef switchTypeRef = sema.typeRefOf(switchRef);
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // Only touch case expressions (not the statements in the case body).
    if (!spanExprRef.isValid())
        return Result::Continue;

    SmallVector<AstNodeRef> expressions;
    sema.ast().nodes(expressions, spanExprRef);
    const bool isExprChild = std::ranges::find(expressions, childRef) != expressions.end();
    if (!isExprChild)
        return Result::Continue;

    // If the switch is on an enum, allow shorthand `case Value:` by rewriting it to an
    // auto-member-access expression (equivalent to `.Value`), which will resolve in the
    // enum scope provided by the binding type pushed from the parent switch.
    if (enumTypeRefFromSwitchType(sema, switchTypeRef).isValid() && sema.node(childRef).is(AstNodeId::Identifier))
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::AutoMemberAccessExpr>(sema.node(childRef).tokRef());
        nodePtr->nodeIdentRef   = childRef;
        childRef                = nodeRef;
    }

    return Result::Continue;
}

namespace
{
    Result castToSwitchType(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view(sema, nodeRef);
        return Cast::cast(sema, view, switchTypeRef, CastKind::Implicit);
    }
}

Result AstSwitchCaseStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        return Cast::cast(sema, nodeView, sema.ctx().typeMgr().typeBool(), CastKind::Condition);
    }

    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const TypeRef switchTypeRef = sema.typeRefOf(switchRef);
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // Only cast case expressions (not the statements in the case body).
    // `childRef` can be one of the expressions in `spanExprRef`.
    if (spanExprRef.isValid())
    {
        SmallVector<AstNodeRef> expressions;
        sema.ast().nodes(expressions, spanExprRef);
        const bool isExprChild = std::ranges::find(expressions, childRef) != expressions.end();

        if (isExprChild)
        {
            // Range expression
            if (sema.node(childRef).is(AstNodeId::RangeExpr))
            {
                const TypeRef   ultimateSwitchTypeRef = sema.typeMgr().get(switchTypeRef).expand(sema.ctx(), switchTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
                const TypeInfo& switchType            = sema.typeMgr().get(ultimateSwitchTypeRef);
                if (!switchType.isScalarNumeric())
                    return SemaError::raise(sema, DiagnosticId::sema_err_switch_range_invalid_type, childRef);

                const auto* range = sema.node(childRef).cast<AstRangeExpr>();
                if (range->nodeExprDownRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprDownRef, switchTypeRef));
                if (range->nodeExprUpRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprUpRef, switchTypeRef));
                return Result::Continue;
            }

            return castToSwitchType(sema, childRef, switchTypeRef);
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
