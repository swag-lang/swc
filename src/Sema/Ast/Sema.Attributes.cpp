#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaFrame.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstAccessModifier::semaPreDecl(Sema& sema) const
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
    sema.pushFrame(newFrame);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAccessModifier::semaPostDecl(Sema& sema)
{
    sema.popFrame();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAccessModifier::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

AstVisitStepResult AstAccessModifier::semaPostNode(Sema& sema)
{
    return semaPostDecl(sema);
}

AstVisitStepResult AstAttrDecl::semaPreDecl(Sema& sema) const
{
    SymbolAttribute& sym = SemaHelpers::declareNamedSymbol<SymbolAttribute>(sema, *this, tokNameRef);

    // Predefined attributes
    if (sym.symMap()->isSwagNamespace(sema.ctx()))
    {
        if (sym.idRef() == sema.idMgr().nameEnumFlags())
            sym.setAttributeFlags(AttributeFlagsE::EnumFlags);
    }

    return AstVisitStepResult::SkipChildren;
}

void AstAttrDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.setDeclared(sema.ctx());
}

AstVisitStepResult AstAttrDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

AstVisitStepResult AstAttrDecl::semaPostNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.setTyped(sema.ctx());
    sym.setCompleted(sema.ctx());
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAttributeList::semaPreNode(Sema& sema)
{
    const SemaFrame newFrame = sema.frame();
    sema.pushFrame(newFrame);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAttributeList::semaPostNode(Sema& sema)
{
    sema.popFrame();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstAttribute::semaPostNode(Sema& sema) const
{
    const Symbol& sym = sema.symbolOf(nodeIdentRef);
    if (!sym.isAttribute())
    {
        SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeIdentRef);
        return AstVisitStepResult::Stop;
    }

    // Predefined attributes
    const SymbolAttribute& attrSym   = sym.cast<SymbolAttribute>();
    const AttributeFlags   attrFlags = attrSym.attributeFlags();
    if (attrFlags != AttributeFlagsE::Zero)
    {
        sema.frame().attributes().addFlag(attrFlags);
        return AstVisitStepResult::Continue;
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;
    sema.frame().attributes().attributes.push_back(inst);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
