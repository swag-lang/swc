#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaMatch.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Sema.h"
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
    auto& ctx = sema.ctx();

    const IdentifierRef idRef     = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);
    const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
    SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);

    SymbolAttribute* sym = Symbol::make<SymbolAttribute>(ctx, srcViewRef(), tokNameRef, idRef, flags);
    if (!symbolMap->addSymbol(ctx, sym, true))
        return AstVisitStepResult::Stop;
    sym->registerCompilerIf(sema);
    sema.setSymbol(sema.curNodeRef(), sym);

    // Predefined attributes
    if (symbolMap->isSwagNamespace(ctx))
    {
        if (sym->idRef() == sema.idMgr().nameEnumFlags())
            sym->setAttributeFlags(AttributeFlagsE::EnumFlags);
    }

    return AstVisitStepResult::Continue;
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
    sym.setComplete(sema.ctx());
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
