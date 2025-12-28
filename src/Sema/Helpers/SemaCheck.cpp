#include "pch.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Main/CompilerInstance.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

Result SemaCheck::modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed)
{
    // Compute unsupported = mods & ~allowed
    const AstModifierFlags unsupported = mods.maskInvert(allowed);
    if (unsupported.none())
        return Result::Success;

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

Result SemaCheck::isValueExpr(Sema& sema, AstNodeRef nodeRef)
{
    const AstNode& node = sema.ast().node(nodeRef);
    if (SemaInfo::hasSemaFlags(node, NodeSemaFlags::ValueExpr))
        return Result::Success;
    const auto diag = SemaError::report(sema, DiagnosticId::sema_err_not_value_expr, nodeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaCheck::isConstant(Sema& sema, AstNodeRef nodeRef)
{
    if (!sema.hasConstant(nodeRef))
    {
        SemaError::raiseExprNotConst(sema, nodeRef);
        return Result::Error;
    }

    return Result::Success;
}

SWC_END_NAMESPACE()
