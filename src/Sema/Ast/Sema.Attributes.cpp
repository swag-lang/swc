#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaFrame.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstAccessModifier::semaPreDecl(Sema& sema) const
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

    SemaFrame newFrame = sema.frame();
    newFrame.setAccess(access);
    sema.pushFrameAutoPopOnPostNode(newFrame);

    return Result::Continue;
}

Result AstAccessModifier::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

Result AstAccessModifier::semaPostNode(Sema& sema)
{
    return semaPostDecl(sema);
}

Result AstAttrDecl::semaPreDecl(Sema& sema) const
{
    SymbolAttribute& sym = SemaHelpers::registerSymbol<SymbolAttribute>(sema, *this, tokNameRef);

    // Predefined attributes
    if (sym.symMap()->isSwagNamespace(sema.ctx()))
    {
        if (sym.idRef() == sema.idMgr().nameEnumFlags())
            sym.setSwagAttributeFlags(SwagAttributeFlagsE::EnumFlags);
        else if (sym.idRef() == sema.idMgr().nameStrict())
            sym.setSwagAttributeFlags(SwagAttributeFlagsE::Strict);
    }

    return Result::SkipChildren;
}

Result AstAttrDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    return Result::Continue;
}

Result AstAttrDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeParamsRef)
        return Result::Continue;

    SymbolAttribute& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolAttribute>();
    sema.pushScopeAutoPopOnPostChild(SemaScopeFlagsE::Parameters, nodeParamsRef);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstAttrDecl::semaPostNode(Sema& sema)
{
    SymbolAttribute& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolAttribute>();
    RESULT_VERIFY(SemaCheck::checkSignature(sema, sym.parameters(), true));
    sym.setTyped(sema.ctx());
    RESULT_VERIFY(Match::ghosting(sema, sym));
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAttributeList::semaPreNode(Sema& sema)
{
    const SemaFrame newFrame = sema.frame();
    sema.pushFrameAutoPopOnPostNode(newFrame);
    return Result::Continue;
}

Result AstAttribute::semaPostNode(Sema& sema) const
{
    const SemaNodeView identView(sema, nodeIdentRef);
    if (!identView.sym)
        return SemaError::raiseInternal(sema, *identView.node);

    if (!identView.sym->isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeIdentRef);

    // Predefined attributes
    const SymbolAttribute&   attrSym   = identView.sym->cast<SymbolAttribute>();
    const SwagAttributeFlags attrFlags = attrSym.swagAttributeFlags();
    if (attrFlags != SwagAttributeFlagsE::Zero)
    {
        sema.frame().attributes().addSwagFlag(attrFlags);
        return Result::Continue;
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;
    sema.frame().attributes().attributes.push_back(inst);

    return Result::Continue;
}

SWC_END_NAMESPACE();
