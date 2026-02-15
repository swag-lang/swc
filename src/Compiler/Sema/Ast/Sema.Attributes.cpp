#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstAccessModifier::semaPreDecl(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());

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
    newFrame.setCurrentAccess(access);
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
            IdentifierRef    id;
            RtAttributeFlags fl;
        };

        const auto& idMgr = sema.idMgr();

        const PredefinedAttr predefined[] = {
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::AttrMulti), .fl = RtAttributeFlagsE::AttrMulti},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::ConstExpr), .fl = RtAttributeFlagsE::ConstExpr},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintBc), .fl = RtAttributeFlagsE::PrintBc},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintBcGen), .fl = RtAttributeFlagsE::PrintBcGen},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PrintAsm), .fl = RtAttributeFlagsE::PrintAsm},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Compiler), .fl = RtAttributeFlagsE::Compiler},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Inline), .fl = RtAttributeFlagsE::Inline},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoInline), .fl = RtAttributeFlagsE::NoInline},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::PlaceHolder), .fl = RtAttributeFlagsE::PlaceHolder},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoPrint), .fl = RtAttributeFlagsE::NoPrint},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Macro), .fl = RtAttributeFlagsE::Macro},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Mixin), .fl = RtAttributeFlagsE::Mixin},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Implicit), .fl = RtAttributeFlagsE::Implicit},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::EnumFlags), .fl = RtAttributeFlagsE::EnumFlags},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::EnumIndex), .fl = RtAttributeFlagsE::EnumIndex},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoDuplicate), .fl = RtAttributeFlagsE::NoDuplicate},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Complete), .fl = RtAttributeFlagsE::Complete},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Overload), .fl = RtAttributeFlagsE::Overload},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::CalleeReturn), .fl = RtAttributeFlagsE::CalleeReturn},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Discardable), .fl = RtAttributeFlagsE::Discardable},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NotGeneric), .fl = RtAttributeFlagsE::NotGeneric},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Tls), .fl = RtAttributeFlagsE::Tls},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoCopy), .fl = RtAttributeFlagsE::NoCopy},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Opaque), .fl = RtAttributeFlagsE::Opaque},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Incomplete), .fl = RtAttributeFlagsE::Incomplete},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::NoDoc), .fl = RtAttributeFlagsE::NoDoc},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Strict), .fl = RtAttributeFlagsE::Strict},
            {.id = idMgr.predefined(IdentifierManager::PredefinedName::Global), .fl = RtAttributeFlagsE::Global},
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
    RESULT_VERIFY(SemaCheck::isValidSignature(sema, sym.parameters(), true));
    sym.setTyped(sema.ctx());
    RESULT_VERIFY(Match::ghosting(sema, sym));
    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAttributeList::semaPreNode(Sema& sema)
{
    const AstNode* parentNode = sema.visit().parentNode();
    if (parentNode && parentNode->is(AstNodeId::CompilerGlobal))
    {
        const auto* parentGlobal = parentNode->cast<AstCompilerGlobal>();
        if (parentGlobal && parentGlobal->mode == AstCompilerGlobal::Mode::AttributeList)
            return Result::Continue;
    }

    const SemaFrame newFrame = sema.frame();
    sema.pushFramePopOnPostNode(newFrame);
    return Result::Continue;
}

Result AstAttribute::semaPostNode(Sema& sema) const
{
    const SemaNodeView identView(sema, nodeIdentRef);
    SWC_ASSERT(identView.sym);
    if (!identView.sym->isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeIdentRef);

    // Predefined attributes
    const SymbolAttribute& attrSym   = identView.sym->cast<SymbolAttribute>();
    const RtAttributeFlags attrFlags = attrSym.rtAttributeFlags();
    if (attrFlags != RtAttributeFlagsE::Zero)
    {
        sema.frame().currentAttributes().addRtFlag(attrFlags);
        return Result::Continue;
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;
    sema.frame().currentAttributes().attributes.push_back(inst);

    return Result::Continue;
}

SWC_END_NAMESPACE();
