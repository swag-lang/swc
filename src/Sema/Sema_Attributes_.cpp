#include "pch.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstAccessModifier::semaPreNode(Sema& sema) const
{
    const Token& tok = sema.token(srcViewRef(), tokRef());

    SymbolAccess access;
    switch (tok.id)
    {
        case TokenId::KwdPrivate:
            access = SymbolAccess::Private;
            break;
        case TokenId::KwdInternal:
            access = SymbolAccess::Internal;
            break;
        case TokenId::KwdPublic:
            access = SymbolAccess::Public;
            break;
        default:
            SWC_UNREACHABLE();
    }

    const AstNode& node = sema.ast().node(nodeWhatRef);
    if (node.is(AstNodeId::TopLevelBlock))
    {
        SemaFrame newFrame     = sema.frame();
        newFrame.defaultAccess = access;
        sema.pushFrame(newFrame);
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAccessModifier::semaPostNode(Sema& sema) const
{
    const AstNode& node = sema.ast().node(nodeWhatRef);
    if (node.is(AstNodeId::TopLevelBlock))
    {
        sema.popFrame();
    }
    
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
