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
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    RtAttributeFlags predefinedRtAttributeFlag(const Sema& sema, IdentifierRef idRef)
    {
        const auto& idMgr = sema.idMgr();

        struct PredefinedRtFlag
        {
            IdentifierManager::PredefinedName name;
            RtAttributeFlags                  flag;
        };

        static constexpr PredefinedRtFlag PREDEFINED_RT_FLAGS[] = {
            {.name = IdentifierManager::PredefinedName::AttrMulti, .flag = RtAttributeFlagsE::AttrMulti},
            {.name = IdentifierManager::PredefinedName::ConstExpr, .flag = RtAttributeFlagsE::ConstExpr},
            {.name = IdentifierManager::PredefinedName::PrintMicro, .flag = RtAttributeFlagsE::PrintMicro},
            {.name = IdentifierManager::PredefinedName::Compiler, .flag = RtAttributeFlagsE::Compiler},
            {.name = IdentifierManager::PredefinedName::Inline, .flag = RtAttributeFlagsE::Inline},
            {.name = IdentifierManager::PredefinedName::NoInline, .flag = RtAttributeFlagsE::NoInline},
            {.name = IdentifierManager::PredefinedName::PlaceHolder, .flag = RtAttributeFlagsE::PlaceHolder},
            {.name = IdentifierManager::PredefinedName::NoPrint, .flag = RtAttributeFlagsE::NoPrint},
            {.name = IdentifierManager::PredefinedName::Macro, .flag = RtAttributeFlagsE::Macro},
            {.name = IdentifierManager::PredefinedName::Mixin, .flag = RtAttributeFlagsE::Mixin},
            {.name = IdentifierManager::PredefinedName::Implicit, .flag = RtAttributeFlagsE::Implicit},
            {.name = IdentifierManager::PredefinedName::EnumFlags, .flag = RtAttributeFlagsE::EnumFlags},
            {.name = IdentifierManager::PredefinedName::EnumIndex, .flag = RtAttributeFlagsE::EnumIndex},
            {.name = IdentifierManager::PredefinedName::NoDuplicate, .flag = RtAttributeFlagsE::NoDuplicate},
            {.name = IdentifierManager::PredefinedName::Complete, .flag = RtAttributeFlagsE::Complete},
            {.name = IdentifierManager::PredefinedName::Overload, .flag = RtAttributeFlagsE::Overload},
            {.name = IdentifierManager::PredefinedName::CalleeReturn, .flag = RtAttributeFlagsE::CalleeReturn},
            {.name = IdentifierManager::PredefinedName::Discardable, .flag = RtAttributeFlagsE::Discardable},
            {.name = IdentifierManager::PredefinedName::NotGeneric, .flag = RtAttributeFlagsE::NotGeneric},
            {.name = IdentifierManager::PredefinedName::Tls, .flag = RtAttributeFlagsE::Tls},
            {.name = IdentifierManager::PredefinedName::NoCopy, .flag = RtAttributeFlagsE::NoCopy},
            {.name = IdentifierManager::PredefinedName::Opaque, .flag = RtAttributeFlagsE::Opaque},
            {.name = IdentifierManager::PredefinedName::Incomplete, .flag = RtAttributeFlagsE::Incomplete},
            {.name = IdentifierManager::PredefinedName::NoDoc, .flag = RtAttributeFlagsE::NoDoc},
            {.name = IdentifierManager::PredefinedName::Strict, .flag = RtAttributeFlagsE::Strict},
            {.name = IdentifierManager::PredefinedName::Global, .flag = RtAttributeFlagsE::Global},
        };

        for (const auto& mapping : PREDEFINED_RT_FLAGS)
        {
            if (idRef == idMgr.predefined(mapping.name))
                return mapping.flag;
        }

        return RtAttributeFlagsE::Zero;
    }

    Result collectAttributeArguments(const Sema& sema, const AstAttribute& nodeAttr, SmallVector<AstNodeRef>& outArgs)
    {
        outArgs.clear();

        if (!nodeAttr.nodeArgsRef.isValid())
            return Result::Continue;

        const auto* argsList = sema.node(nodeAttr.nodeArgsRef).safeCast<AstNamedArgumentList>();
        SWC_ASSERT(argsList != nullptr);

        SmallVector<AstNodeRef> args;
        sema.ast().appendNodes(args, argsList->spanChildrenRef);

        for (const AstNodeRef argRef : args)
        {
            AstNodeRef finalArgRef = sema.getSubstituteRef(argRef);
            if (finalArgRef.isInvalid())
                finalArgRef = argRef;
            outArgs.push_back(finalArgRef);
        }

        return Result::Continue;
    }

    AstNodeRef resolveAttributeArgValueRef(const Sema& sema, AstNodeRef argRef)
    {
        AstNodeRef finalArgRef = sema.getSubstituteRef(argRef);
        if (finalArgRef.isInvalid())
            finalArgRef = argRef;

        if (const auto* namedArg = sema.node(finalArgRef).safeCast<AstNamedArgument>())
        {
            AstNodeRef valueRef = sema.getSubstituteRef(namedArg->nodeArgRef);
            if (valueRef.isInvalid())
                valueRef = namedArg->nodeArgRef;
            return valueRef;
        }

        return finalArgRef;
    }

    Result matchAttributeArguments(const SymbolAttribute*& outAttrSym, Sema& sema, const SemaNodeView& identView, std::span<const AstNodeRef> args)
    {
        outAttrSym = nullptr;

        SmallVector<Symbol*> symbols;
        identView.getSymbols(symbols);
        if (symbols.empty() && identView.sym)
            symbols.push_back(const_cast<Symbol*>(identView.sym));

        SmallVector<const SymbolAttribute*> attrCandidates;
        for (const Symbol* sym : symbols)
        {
            if (!sym || !sym->isAttribute())
                continue;
            attrCandidates.push_back(&sym->cast<SymbolAttribute>());
        }

        if (attrCandidates.empty())
            return Result::Error;

        for (const SymbolAttribute* attrSym : attrCandidates)
            RESULT_VERIFY(sema.waitSemaCompleted(attrSym, identView.node->codeRef()));

        SmallVector<SymbolFunction*> fnAdapters;
        SmallVector<Symbol*>         fnSymbols;
        fnAdapters.reserve(attrCandidates.size());
        fnSymbols.reserve(attrCandidates.size());

        for (const SymbolAttribute* attrSym : attrCandidates)
        {
            auto* fnAdapter = Symbol::make<SymbolFunction>(sema.ctx(), attrSym->decl(), attrSym->tokRef(), attrSym->idRef(), SymbolFlagsE::Zero);
            fnAdapter->setReturnTypeRef(sema.typeMgr().typeVoid());
            for (SymbolVariable* param : attrSym->parameters())
                fnAdapter->addParameter(param);
            const TypeRef fnTypeRef = sema.typeMgr().addType(TypeInfo::makeFunction(fnAdapter, TypeInfoFlagsE::Zero));
            fnAdapter->setTypeRef(fnTypeRef);

            fnSymbols.push_back(fnAdapter);
            fnAdapters.push_back(fnAdapter);
        }

        SmallVector<AstNodeRef> callArgs;
        callArgs.reserve(args.size());
        for (const AstNodeRef argRef : args)
            callArgs.push_back(argRef);
        RESULT_VERIFY(Match::resolveFunctionCandidates(sema, identView, fnSymbols.span(), callArgs.span()));

        const Symbol* selectedFnSym = &sema.symbolOf(sema.curNodeRef());
        for (uint32_t i = 0; i < fnAdapters.size(); ++i)
        {
            if (fnAdapters[i] == selectedFnSym)
            {
                outAttrSym = attrCandidates[i];
                sema.setSymbol(sema.curNodeRef(), outAttrSym);
                return Result::Continue;
            }
        }

        return Result::Error;
    }

    Result collectPrintMicroOptions(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        if (args.empty())
        {
            outAttributes.printMicroPassOptions.push_back(Utf8{"before-emit"});
            return Result::Continue;
        }

        for (const auto argValueRef : args)
        {
            RESULT_VERIFY(SemaCheck::isConstant(sema, argValueRef));
            const SemaNodeView argView = sema.nodeView(argValueRef);
            if (!argView.cst->isString())
                return SemaError::raiseInvalidType(sema, argValueRef, argView.typeRef, sema.typeMgr().typeString());
            outAttributes.printMicroPassOptions.push_back(Utf8{argView.cst->getString()});
        }

        return Result::Continue;
    }

    Result collectOptimizeLevel(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        const AstNodeRef argValueRef = args[0];
        RESULT_VERIFY(SemaCheck::isConstant(sema, argValueRef));

        const SemaNodeView   argView = sema.nodeView(argValueRef);
        const ConstantValue* value   = argView.cst;
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

    Result collectPredefinedAttributeData(Sema& sema, std::span<const AstNodeRef> args, const SymbolAttribute& attrSym, AttributeList& outAttributes)
    {
        if (!attrSym.inSwagNamespace(sema.ctx()))
            return Result::Continue;

        const auto&         idMgr = sema.idMgr();
        const IdentifierRef idRef = attrSym.idRef();
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Optimize))
            return collectOptimizeLevel(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return collectPrintMicroOptions(sema, args, outAttributes);
        return Result::Continue;
    }

    void collectAttributeArgumentValues(const Sema& sema, std::span<const AstNodeRef> args, SmallVector<AstNodeRef>& outValues)
    {
        outValues.clear();
        outValues.reserve(args.size());
        for (const AstNodeRef argRef : args)
            outValues.push_back(resolveAttributeArgValueRef(sema, argRef));
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

    SmallVector<AstNodeRef> args;
    RESULT_VERIFY(collectAttributeArguments(sema, *this, args));

    const SymbolAttribute* attrSym = nullptr;
    RESULT_VERIFY(matchAttributeArguments(attrSym, sema, identView, args.span()));
    SWC_ASSERT(attrSym != nullptr);

    SmallVector<AstNodeRef> argValues;
    collectAttributeArgumentValues(sema, args.span(), argValues);
    RESULT_VERIFY(collectPredefinedAttributeData(sema, argValues.span(), *attrSym, sema.frame().currentAttributes()));

    const RtAttributeFlags attrFlags = attrSym->rtAttributeFlags();
    if (attrFlags != RtAttributeFlagsE::Zero)
    {
        sema.frame().currentAttributes().addRtFlag(attrFlags);
        return Result::Continue;
    }

    AttributeInstance inst;
    inst.symbol = attrSym;
    sema.frame().currentAttributes().attributes.push_back(inst);

    return Result::Continue;
}

SWC_END_NAMESPACE();
