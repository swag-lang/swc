#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaFrame.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

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
    sema.pushFrame(newFrame);

    return Result::Continue;
}

Result AstAccessModifier::semaPostDecl(Sema& sema)
{
    sema.popFrame();
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
            sym.setAttributeFlags(AttributeFlagsE::EnumFlags);
        else if (sym.idRef() == sema.idMgr().nameStrict())
            sym.setAttributeFlags(AttributeFlagsE::Strict);
    }

    return Result::SkipChildren;
}

Result AstAttrDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

Result AstAttrDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return Result::SkipChildren; // TODO
    if (childRef != nodeParamsRef)
        return Result::Continue;

    SymbolAttribute& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolAttribute>();
    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return Result::Continue;
}

Result AstAttrDecl::semaPostNode(Sema& sema)
{
    SymbolAttribute& sym      = sema.symbolOf(sema.curNodeRef()).cast<SymbolAttribute>();
    /*const auto*      nodeAttr = sema.node(sema.curNodeRef()).cast<AstAttrDecl>();

    if (nodeAttr->nodeParamsRef.isValid())
    {
        const auto* params = sema.node(nodeAttr->nodeParamsRef).cast<AstFunctionParamList>();

        SmallVector<AstNodeRef> children;
        sema.ast().nodes(children, params->spanChildrenRef);
        for (const auto& child : children)
        {
            auto& symVar = sema.symbolOf(child).cast<SymbolVariable>();
            sym.parameters().push_back(&symVar);
        }

        sema.popScope();
    }*/

    sym.setTyped(sema.ctx());
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAttributeList::semaPreNode(Sema& sema)
{
    const SemaFrame newFrame = sema.frame();
    sema.pushFrame(newFrame);
    return Result::Continue;
}

Result AstAttributeList::semaPostNode(Sema& sema)
{
    sema.popFrame();
    return Result::Continue;
}

Result AstAttribute::semaPostNode(Sema& sema) const
{
    const Symbol& sym = sema.symbolOf(nodeIdentRef);
    if (!sym.isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeIdentRef);

    // Predefined attributes
    const SymbolAttribute& attrSym   = sym.cast<SymbolAttribute>();
    const AttributeFlags   attrFlags = attrSym.attributeFlags();
    if (attrFlags != AttributeFlagsE::Zero)
    {
        sema.frame().attributes().addFlag(attrFlags);
        return Result::Continue;
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;
    sema.frame().attributes().attributes.push_back(inst);

    return Result::Continue;
}

SWC_END_NAMESPACE()
