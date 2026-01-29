#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
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
    sema.pushFramePopOnPostNode(newFrame);

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
    if (sym.inSwagNamespace(sema.ctx()))
    {
        struct PredefinedAttr
        {
            IdentifierRef      id;
            SwagAttributeFlags fl;
        };

        const auto& idMgr = sema.idMgr();

        const PredefinedAttr predefined[] = {
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::AttrMulti), .fl = SwagAttributeFlagsE::AttrMulti},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::ConstExpr), .fl = SwagAttributeFlagsE::ConstExpr},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintBc), .fl = SwagAttributeFlagsE::PrintBc},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintBcGen), .fl = SwagAttributeFlagsE::PrintBcGen},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintAsm), .fl = SwagAttributeFlagsE::PrintAsm},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Compiler), .fl = SwagAttributeFlagsE::Compiler},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Inline), .fl = SwagAttributeFlagsE::Inline},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoInline), .fl = SwagAttributeFlagsE::NoInline},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PlaceHolder), .fl = SwagAttributeFlagsE::PlaceHolder},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoPrint), .fl = SwagAttributeFlagsE::NoPrint},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Macro), .fl = SwagAttributeFlagsE::Macro},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Mixin), .fl = SwagAttributeFlagsE::Mixin},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Implicit), .fl = SwagAttributeFlagsE::Implicit},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::EnumFlags), .fl = SwagAttributeFlagsE::EnumFlags},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::EnumIndex), .fl = SwagAttributeFlagsE::EnumIndex},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoDuplicate), .fl = SwagAttributeFlagsE::NoDuplicate},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Complete), .fl = SwagAttributeFlagsE::Complete},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Overload), .fl = SwagAttributeFlagsE::Overload},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::CalleeReturn), .fl = SwagAttributeFlagsE::CalleeReturn},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Discardable), .fl = SwagAttributeFlagsE::Discardable},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NotGeneric), .fl = SwagAttributeFlagsE::NotGeneric},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Tls), .fl = SwagAttributeFlagsE::Tls},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoCopy), .fl = SwagAttributeFlagsE::NoCopy},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Opaque), .fl = SwagAttributeFlagsE::Opaque},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Incomplete), .fl = SwagAttributeFlagsE::Incomplete},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoDoc), .fl = SwagAttributeFlagsE::NoDoc},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Strict), .fl = SwagAttributeFlagsE::Strict},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Global), .fl = SwagAttributeFlagsE::Global},
        };

        const IdentifierRef idRef = sym.idRef();
        for (const auto& it : predefined)
        {
            if (idRef == it.id)
            {
                sym.setRtAttributeFlags(it.fl);
                break;
            }
        }
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
    sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, nodeParamsRef);
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
    sema.pushFramePopOnPostNode(newFrame);
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
    const SwagAttributeFlags attrFlags = attrSym.rtAttributeFlags();
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
