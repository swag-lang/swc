#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef unwrapNamedArgumentValue(const Sema& sema, AstNodeRef argValueRef)
    {
        if (const auto* namedArg = sema.node(argValueRef).safeCast<AstNamedArgument>())
            return namedArg->nodeArgRef;
        return argValueRef;
    }

    SmallVector<AstNodeRef> collectAttributeArgs(const Sema& sema, const AstAttribute& nodeAttr)
    {
        SmallVector<AstNodeRef> outArgs;
        if (nodeAttr.nodeArgsRef.isInvalid())
            return outArgs;

        const auto* argsList = sema.node(nodeAttr.nodeArgsRef).safeCast<AstNamedArgumentList>();
        SWC_ASSERT(argsList != nullptr);
        if (!argsList)
            return outArgs;

        sema.ast().appendNodes(outArgs, argsList->spanChildrenRef);
        for (auto& argRef : outArgs)
            argRef = unwrapNamedArgumentValue(sema, argRef);
        return outArgs;
    }

    RtAttributeFlags predefinedRtAttributeFlag(const Sema& sema, IdentifierRef idRef)
    {
        const auto& idMgr = sema.idMgr();

        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::AttrMulti))
            return RtAttributeFlagsE::AttrMulti;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::ConstExpr))
            return RtAttributeFlagsE::ConstExpr;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return RtAttributeFlagsE::PrintMicro;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Compiler))
            return RtAttributeFlagsE::Compiler;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Inline))
            return RtAttributeFlagsE::Inline;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NoInline))
            return RtAttributeFlagsE::NoInline;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PlaceHolder))
            return RtAttributeFlagsE::PlaceHolder;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NoPrint))
            return RtAttributeFlagsE::NoPrint;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Macro))
            return RtAttributeFlagsE::Macro;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Mixin))
            return RtAttributeFlagsE::Mixin;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Implicit))
            return RtAttributeFlagsE::Implicit;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::EnumFlags))
            return RtAttributeFlagsE::EnumFlags;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::EnumIndex))
            return RtAttributeFlagsE::EnumIndex;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NoDuplicate))
            return RtAttributeFlagsE::NoDuplicate;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Complete))
            return RtAttributeFlagsE::Complete;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Overload))
            return RtAttributeFlagsE::Overload;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::CalleeReturn))
            return RtAttributeFlagsE::CalleeReturn;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Discardable))
            return RtAttributeFlagsE::Discardable;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NotGeneric))
            return RtAttributeFlagsE::NotGeneric;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Tls))
            return RtAttributeFlagsE::Tls;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NoCopy))
            return RtAttributeFlagsE::NoCopy;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Opaque))
            return RtAttributeFlagsE::Opaque;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Incomplete))
            return RtAttributeFlagsE::Incomplete;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::NoDoc))
            return RtAttributeFlagsE::NoDoc;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Strict))
            return RtAttributeFlagsE::Strict;
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Global))
            return RtAttributeFlagsE::Global;

        return RtAttributeFlagsE::Zero;
    }

    Result collectPrintMicroOptions(Sema& sema, const AstAttribute& nodeAttr, AttributeList& outAttributes)
    {
        const auto args = collectAttributeArgs(sema, nodeAttr);
        if (args.empty())
        {
            outAttributes.printMicroPassOptions.push_back(Utf8{"before-emit"});
            return Result::Continue;
        }

        for (const auto argValueRef : args)
        {
            const SemaNodeView argView = sema.nodeView(argValueRef);
            SWC_ASSERT(argView.cst != nullptr);
            if (!argView.cst)
                return SemaError::raiseExprNotConst(sema, argValueRef);

            if (!argView.cst->isString())
                return SemaError::raiseInvalidType(sema, argValueRef, argView.typeRef, sema.typeMgr().typeString());

            outAttributes.printMicroPassOptions.push_back(Utf8{argView.cst->getString()});
        }

        return Result::Continue;
    }

    Result collectOptimizeLevel(Sema& sema, const AstAttribute& nodeAttr, const SymbolAttribute& attrSym, AttributeList& outAttributes)
    {
        SWC_ASSERT(attrSym.parameters().size() == 1);
        if (attrSym.parameters().size() != 1)
            return Result::Continue;

        const auto args = collectAttributeArgs(sema, nodeAttr);
        SWC_ASSERT(args.size() == attrSym.parameters().size());
        if (args.size() != attrSym.parameters().size())
            return Result::Continue;

        const AstNodeRef argValueRef = args[0];

        const SemaNodeView argView = sema.nodeView(argValueRef);
        SWC_ASSERT(argView.cst != nullptr);
        if (!argView.cst)
            return SemaError::raiseExprNotConst(sema, argValueRef);

        const ConstantValue* value = argView.cst;
        if (value->isEnumValue())
            value = &sema.ctx().cstMgr().get(value->getEnumValue());

        if (!value->isInt())
            return SemaError::raiseInvalidType(sema, argValueRef, argView.typeRef, sema.typeMgr().typeS32());

        const int64_t levelI64 = value->getInt().asI64();
        if (levelI64 < 0 || levelI64 > static_cast<int64_t>(Runtime::BuildCfgBackendOptim::Oz))
            return SemaError::raiseInvalidType(sema, argValueRef, argView.typeRef, sema.typeMgr().typeS32());

        outAttributes.setBackendOptimize(static_cast<Runtime::BuildCfgBackendOptim>(levelI64));
        return Result::Continue;
    }

    Result collectPredefinedAttributeData(Sema& sema, const AstAttribute& nodeAttr, const SymbolAttribute& attrSym, AttributeList& outAttributes)
    {
        if (!attrSym.inSwagNamespace(sema.ctx()))
            return Result::Continue;

        const auto&         idMgr = sema.idMgr();
        const IdentifierRef idRef = attrSym.idRef();
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Optimize))
            return collectOptimizeLevel(sema, nodeAttr, attrSym, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return collectPrintMicroOptions(sema, nodeAttr, outAttributes);
        return Result::Continue;
    }
}

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
        const RtAttributeFlags attrFlag = predefinedRtAttributeFlag(sema, sym.idRef());
        if (attrFlag != RtAttributeFlagsE::Zero)
            sym.setRtAttributeFlags(attrFlag);
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
    const SemaNodeView identView = sema.nodeView(nodeIdentRef);
    SWC_ASSERT(identView.sym);
    if (!identView.sym->isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeIdentRef);

    const SymbolAttribute& attrSym = identView.sym->cast<SymbolAttribute>();
    RESULT_VERIFY(collectPredefinedAttributeData(sema, *this, attrSym, sema.frame().currentAttributes()));

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
