#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Ast/AstPrinter.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_AST_STAGE_PRE_SEMA  = "pre-sema";
    constexpr std::string_view K_AST_STAGE_POST_SEMA = "post-sema";

    bool shouldPrintAstStage(const AttributeList& attributes, std::string_view stageName)
    {
        for (const Utf8& stage : attributes.printAstStageOptions)
        {
            if (std::string_view{stage} == stageName)
                return true;
        }

        return false;
    }

    void printAstStage(Sema& sema, AstNodeRef nodeRef, std::string_view stageName)
    {
        const AstNode&        node     = sema.node(nodeRef);
        const TaskContext&    ctx      = sema.ctx();
        const SourceCodeRange codeLoc  = node.codeRange(ctx);
        const SourceView&     srcView  = sema.srcView(node.srcViewRef());
        const SourceFile*     srcFile  = srcView.file();
        const Utf8            filePath = srcFile ? FileSystem::formatFileLocation(&ctx, srcFile->path(), codeLoc.line) : Utf8("<unknown-file>");

        const Logger::ScopedLock lock(ctx.global().logger());
        Logger::print(ctx, "\n");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Compiler));
        Logger::print(ctx, "[ast]");
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  stage");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "    : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Attribute));
        Logger::print(ctx, stageName);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  node");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "     : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Type));
        Logger::print(ctx, Ast::nodeIdName(node.id()));
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " #");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::InstructionIndex));
        Logger::print(ctx, std::format("{}", nodeRef.get()));
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  location");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::String));
        Logger::print(ctx, filePath);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
        AstPrinter::print(ctx, sema.ast(), nodeRef, &sema);
    }

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
            {.name = IdentifierManager::PredefinedName::PrintAst, .flag = RtAttributeFlagsE::PrintAst},
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

    Result validateRtAttributeConstraints(Sema& sema, const AttributeList& currentAttributes, RtAttributeFlags attrFlags, AstNodeRef errorRef)
    {
        const bool hasInline   = currentAttributes.hasRtFlag(RtAttributeFlagsE::Inline);
        const bool hasNoInline = currentAttributes.hasRtFlag(RtAttributeFlagsE::NoInline);
        if ((attrFlags.has(RtAttributeFlagsE::Inline) && hasNoInline) ||
            (attrFlags.has(RtAttributeFlagsE::NoInline) && hasInline))
        {
            return SemaError::raise(sema, DiagnosticId::sema_err_attribute_inline_noinline_conflict, errorRef);
        }

        const bool nextHasInline = hasInline || attrFlags.has(RtAttributeFlagsE::Inline);
        const bool nextHasMacro  = currentAttributes.hasRtFlag(RtAttributeFlagsE::Macro) || attrFlags.has(RtAttributeFlagsE::Macro);
        const bool nextHasMixin  = currentAttributes.hasRtFlag(RtAttributeFlagsE::Mixin) || attrFlags.has(RtAttributeFlagsE::Mixin);
        if ((nextHasInline && nextHasMacro) || (nextHasInline && nextHasMixin) || (nextHasMacro && nextHasMixin))
            return SemaError::raise(sema, DiagnosticId::sema_err_attribute_inline_macro_mixin_conflict, errorRef);

        return Result::Continue;
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
            SWC_RESULT(SemaCheck::isConstant(sema, argValueRef));
            const SemaNodeView argView = sema.viewConstant(argValueRef);
            outAttributes.printMicroPassOptions.push_back(Utf8{argView.cst()->getString()});
        }

        return Result::Continue;
    }

    Result collectPrintAstOptions(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        if (args.empty())
        {
            outAttributes.printAstStageOptions.push_back(Utf8{"post-sema"});
            return Result::Continue;
        }

        for (const auto argValueRef : args)
        {
            SWC_RESULT(SemaCheck::isConstant(sema, argValueRef));
            const SemaNodeView argView = sema.viewConstant(argValueRef);
            outAttributes.printAstStageOptions.push_back(Utf8{argView.cst()->getString()});
        }

        return Result::Continue;
    }

    Result collectOptimizeLevel(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        const AstNodeRef argValueRef = args[0];
        SWC_RESULT(SemaCheck::isConstant(sema, argValueRef));

        const SemaNodeView argView = sema.viewConstant(argValueRef);
        SWC_ASSERT(argView.cst() != nullptr);
        SWC_ASSERT(argView.cst()->isBool());
        outAttributes.setBackendOptimize(argView.cst()->getBool());

        return Result::Continue;
    }

    Result collectForeignStringValue(Sema& sema, Utf8& outValue, const ResolvedCallArgument& arg)
    {
        outValue.clear();
        if (arg.argRef.isValid())
        {
            SWC_RESULT(SemaCheck::isConstant(sema, arg.argRef));
            const SemaNodeView argView = sema.viewConstant(arg.argRef);
            SWC_ASSERT(argView.cst() != nullptr);
            SWC_ASSERT(argView.cst()->isString());
            outValue = Utf8{argView.cst()->getString()};
            return Result::Continue;
        }

        if (!arg.defaultCstRef.isValid())
            return Result::Continue;

        const ConstantValue& constant = sema.cstMgr().get(arg.defaultCstRef);
        SWC_ASSERT(constant.isString());
        outValue = Utf8{constant.getString()};
        return Result::Continue;
    }

    Result collectForeignOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(!args.empty());

        Utf8 moduleName;
        Utf8 functionName;
        Utf8 linkModuleName;
        SWC_RESULT(collectForeignStringValue(sema, moduleName, args[0]));
        if (args.size() > 1)
            SWC_RESULT(collectForeignStringValue(sema, functionName, args[1]));
        if (args.size() > 2)
            SWC_RESULT(collectForeignStringValue(sema, linkModuleName, args[2]));

        outAttributes.setForeign(moduleName, functionName, linkModuleName);
        return Result::Continue;
    }

    Result collectPredefinedAttributeData(Sema& sema, std::span<const AstNodeRef> args, std::span<const ResolvedCallArgument> resolvedArgs, const SymbolFunction& attrSym, AttributeList& outAttributes)
    {
        if (!attrSym.inSwagNamespace(sema.ctx()))
            return Result::Continue;

        const IdentifierManager& idMgr = sema.idMgr();
        const IdentifierRef      idRef = attrSym.idRef();
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Optimize))
            return collectOptimizeLevel(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return collectPrintMicroOptions(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintAst))
            return collectPrintAstOptions(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Foreign))
            return collectForeignOptions(sema, resolvedArgs, outAttributes);
        return Result::Continue;
    }

}

Result AstAccessModifier::semaPreDecl(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());

    SymbolAccess access;
    switch (tok.id)
    {
        case TokenId::KwdModulePrivate:
            access = SymbolAccess::ModulePrivate;
            break;
        case TokenId::KwdFilePrivate:
            access = SymbolAccess::FilePrivate;
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
    auto& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);
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

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, nodeParamsRef);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstAttrDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    sym.setReturnTypeRef(sema.typeMgr().typeVoid());
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero));
    sym.setTypeRef(typeRef);
    SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), true));
    sym.setTyped(sema.ctx());
    SWC_RESULT(Match::ghosting(sema, sym));
    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAttributeList::semaPreNode(Sema& sema)
{
    const AstNode* parentNode = sema.visit().parentNode();
    if (parentNode && parentNode->is(AstNodeId::CompilerGlobal))
    {
        const auto& parentGlobal = parentNode->cast<AstCompilerGlobal>();
        if (parentGlobal.mode == AstCompilerGlobal::Mode::AttributeList)
            return Result::Continue;
    }

    const SemaFrame newFrame = sema.frame();
    sema.pushFramePopOnPostNode(newFrame);
    return Result::Continue;
}

Result AstAttributeList::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (nodeBodyRef.isInvalid())
        return Result::Continue;

    const AttributeList& attributes = sema.frame().currentAttributes();
    if (!attributes.hasRtFlag(RtAttributeFlagsE::PrintAst))
        return Result::Continue;

    if (!shouldPrintAstStage(attributes, K_AST_STAGE_PRE_SEMA))
        return Result::Continue;

    printAstStage(sema, nodeBodyRef, K_AST_STAGE_PRE_SEMA);
    return Result::Continue;
}

Result AstAttributeList::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (nodeBodyRef.isInvalid())
        return Result::Continue;

    const AttributeList& attributes = sema.frame().currentAttributes();
    if (!attributes.hasRtFlag(RtAttributeFlagsE::PrintAst))
        return Result::Continue;

    if (!shouldPrintAstStage(attributes, K_AST_STAGE_POST_SEMA))
        return Result::Continue;

    printAstStage(sema, nodeBodyRef, K_AST_STAGE_POST_SEMA);
    return Result::Continue;
}

Result AstAttribute::semaPostNode(Sema& sema) const
{
    const AstCallExpr& callNode = sema.node(nodeCallRef).cast<AstCallExpr>();

    const SemaNodeView callView = sema.viewSymbol(nodeCallRef);
    SWC_ASSERT(callView.sym());

    AstNodeRef errorRef = nodeCallRef;
    if (callNode.nodeExprRef.isValid())
        errorRef = callNode.nodeExprRef;

    if (!callView.sym()->isAttribute())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, errorRef);

    const SymbolFunction& attrSym = callView.sym()->cast<SymbolFunction>();

    SmallVector<AstNodeRef> args;
    callNode.collectArguments(args, sema.ast());
    SmallVector<AstNodeRef> argValues;
    Match::resolveCallArgumentValues(sema, argValues, args.span());
    SmallVector<ResolvedCallArgument> resolvedArgs;
    sema.appendResolvedCallArguments(nodeCallRef, resolvedArgs);
    SWC_RESULT(collectPredefinedAttributeData(sema, argValues.span(), resolvedArgs.span(), attrSym, sema.frame().currentAttributes()));

    const RtAttributeFlags attrFlags = attrSym.rtAttributeFlags();
    if (attrFlags != RtAttributeFlagsE::Zero)
    {
        const AttributeList& currentAttributes = sema.frame().currentAttributes();
        SWC_RESULT(validateRtAttributeConstraints(sema, currentAttributes, attrFlags, errorRef));

        sema.frame().currentAttributes().addRtFlag(attrFlags);
        return Result::Continue;
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;
    sema.frame().currentAttributes().attributes.push_back(inst);

    return Result::Continue;
}

SWC_END_NAMESPACE();
