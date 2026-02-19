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
        const IdentifierManager& idMgr = sema.idMgr();

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

    Result collectPrintMicroOptions(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        if (args.empty())
        {
            outAttributes.printMicroPassOptions.push_back(Utf8{"pre-emit"});
            return Result::Continue;
        }

        for (const auto argValueRef : args)
        {
            RESULT_VERIFY(SemaCheck::isConstant(sema, argValueRef));
            const SemaNodeView argView = sema.nodeViewConstant(argValueRef);
            outAttributes.printMicroPassOptions.push_back(Utf8{argView.cst->getString()});
        }

        return Result::Continue;
    }

    Result collectOptimizeLevel(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        const AstNodeRef argValueRef = args[0];
        RESULT_VERIFY(SemaCheck::isConstant(sema, argValueRef));

        const SemaNodeView argView = sema.nodeViewConstant(argValueRef);
        SWC_ASSERT(argView.cst != nullptr);
        SWC_ASSERT(argView.cst->isEnumValue());

        const ConstantValue& levelValue = sema.ctx().cstMgr().get(argView.cst->getEnumValue());
        SWC_ASSERT(levelValue.isInt());
        const int64_t levelI64 = levelValue.getInt().asI64();
        outAttributes.setBackendOptimize(static_cast<Runtime::BuildCfgBackendOptim>(levelI64));

        return Result::Continue;
    }

    Result collectForeignOptions(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(!args.empty());

        const AstNodeRef moduleValueRef = args[0];
        RESULT_VERIFY(SemaCheck::isConstant(sema, moduleValueRef));
        const SemaNodeView moduleView = sema.nodeViewConstant(moduleValueRef);
        SWC_ASSERT(moduleView.cst != nullptr);
        if (!moduleView.cst->isString())
            return SemaError::raiseInvalidType(sema, moduleValueRef, moduleView.cst->typeRef(), sema.typeMgr().typeString());

        std::string_view functionName;
        if (args.size() > 1)
        {
            const AstNodeRef functionValueRef = args[1];
            RESULT_VERIFY(SemaCheck::isConstant(sema, functionValueRef));
            const SemaNodeView functionView = sema.nodeViewConstant(functionValueRef);
            SWC_ASSERT(functionView.cst != nullptr);
            if (!functionView.cst->isString())
                return SemaError::raiseInvalidType(sema, functionValueRef, functionView.cst->typeRef(), sema.typeMgr().typeString());
            functionName = functionView.cst->getString();
        }

        outAttributes.setForeign(moduleView.cst->getString(), functionName);
        return Result::Continue;
    }

    Result collectPredefinedAttributeData(Sema& sema, std::span<const AstNodeRef> args, const SymbolFunction& attrSym, AttributeList& outAttributes)
    {
        if (!attrSym.inSwagNamespace(sema.ctx()))
            return Result::Continue;

        const IdentifierManager& idMgr = sema.idMgr();
        const IdentifierRef      idRef = attrSym.idRef();
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Optimize))
            return collectOptimizeLevel(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return collectPrintMicroOptions(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Foreign))
            return collectForeignOptions(sema, args, outAttributes);
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

Result AstAccessModifier::semaPostNode(const Sema& sema)
{
    return semaPostDecl(sema);
}

Result AstAttrDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);
    sym.addExtraFlag(SymbolFunctionFlagsE::Attribute);

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

    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, nodeParamsRef);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstAttrDecl::semaPostNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setReturnTypeRef(sema.typeMgr().typeVoid());
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero));
    sym.setTypeRef(typeRef);
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
        const AstCompilerGlobal* parentGlobal = parentNode->cast<AstCompilerGlobal>();
        if (parentGlobal && parentGlobal->mode == AstCompilerGlobal::Mode::AttributeList)
            return Result::Continue;
    }

    const SemaFrame newFrame = sema.frame();
    sema.pushFramePopOnPostNode(newFrame);
    return Result::Continue;
}

Result AstAttribute::semaPostNode(Sema& sema) const
{
    const AstCallExpr* callNode = sema.node(nodeCallRef).safeCast<AstCallExpr>();
    SWC_ASSERT(callNode != nullptr);

    const SemaNodeView callView = sema.nodeViewSymbol(nodeCallRef);
    SWC_ASSERT(callView.sym);

    AstNodeRef errorRef = nodeCallRef;
    if (callNode->nodeExprRef.isValid())
        errorRef = callNode->nodeExprRef;

    if (!callView.sym->isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, errorRef);

    const SymbolFunction* attrSym = callView.sym->safeCast<SymbolFunction>();
    SWC_ASSERT(attrSym != nullptr);

    SmallVector<AstNodeRef> args;
    callNode->collectArguments(args, sema.ast());
    SmallVector<AstNodeRef> argValues;
    Match::resolveCallArgumentValues(sema, argValues, args.span());
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

