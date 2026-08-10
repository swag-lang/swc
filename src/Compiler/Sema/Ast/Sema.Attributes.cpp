#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Ast/AstPrinter.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Main/Global.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"
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

    void addUsingSymMapToScope(SemaScope& scope, SymbolMap* usingSymMap)
    {
        SWC_ASSERT(usingSymMap != nullptr);
        for (const SymbolMap* existing : scope.usingSymMaps())
        {
            if (existing == usingSymMap)
                return;
        }

        scope.addUsingSymMap(usingSymMap);
    }

    bool isSwagUsingAttribute(const Sema& sema, const AttributeInstance& attribute)
    {
        if (!attribute.symbol)
            return false;
        return attribute.symbol->inSwagNamespace(sema.ctx()) && attribute.symbol->name(sema.ctx()) == "Using";
    }

    TypeRef attributeParamTypeValueRef(Sema& sema, const AttributeParamInstance& param)
    {
        if (!param.valueCstRef.isValid())
            return TypeRef::invalid();

        const ConstantValue& value = sema.cstMgr().get(param.valueCstRef);
        if (value.isTypeValue())
            return value.getTypeValue();
        return sema.cstMgr().makeTypeValue(sema, param.valueCstRef);
    }

    SymbolMap* usingAttributeSymMap(Sema& sema, const AttributeParamInstance& param)
    {
        const TypeRef typeRef = attributeParamTypeValueRef(sema, param);
        if (typeRef.isInvalid())
            return nullptr;

        const TypeInfo& typeInfo         = sema.typeMgr().get(typeRef);
        const TypeRef   unwrappedTypeRef = typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        if (unwrappedTypeRef.isInvalid())
            return nullptr;

        Symbol* symbol = sema.typeMgr().get(unwrappedTypeRef).getSymbol();
        if (!symbol || !symbol->isSymMap())
            return nullptr;

        return symbol->asSymMap();
    }

    void addSwagUsingAttributeSymMaps(Sema& sema, SemaScope& scope, const AttributeInstance& attribute)
    {
        if (!isSwagUsingAttribute(sema, attribute))
            return;

        for (const AttributeParamInstance& param : attribute.params)
        {
            if (SymbolMap* usingSymMap = usingAttributeSymMap(sema, param))
                addUsingSymMapToScope(scope, usingSymMap);
        }
    }

    void addSwagUsingAttributeSymMaps(Sema& sema, SemaScope& scope, const AttributeList& attributes)
    {
        for (const AttributeInstance& attribute : attributes.attributes)
            addSwagUsingAttributeSymMaps(sema, scope, attribute);
    }

    void printAstStage(Sema& sema, AstNodeRef nodeRef, std::string_view stageName)
    {
        const AstNode&        node     = sema.node(nodeRef);
        const TaskContext&    ctx      = sema.ctx();
        const SourceCodeRange codeLoc  = node.codeRange(ctx);
        const SourceView&     srcView  = sema.srcView(node.srcViewRef());
        const SourceFile*     srcFile  = srcView.file();
        const Utf8            filePath = srcFile ? srcFile->formatFileLocation(&ctx, codeLoc.line) : Utf8("<unknown-file>");

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
            {.name = IdentifierManager::PredefinedName::NoDuplicate, .flag = RtAttributeFlagsE::NoDuplicate},
            {.name = IdentifierManager::PredefinedName::FullInit, .flag = RtAttributeFlagsE::FullInit},
            {.name = IdentifierManager::PredefinedName::Late, .flag = RtAttributeFlagsE::Late},
            {.name = IdentifierManager::PredefinedName::CalleeReturn, .flag = RtAttributeFlagsE::CalleeReturn},
            {.name = IdentifierManager::PredefinedName::Discardable, .flag = RtAttributeFlagsE::Discardable},
            {.name = IdentifierManager::PredefinedName::Tls, .flag = RtAttributeFlagsE::Tls},
            {.name = IdentifierManager::PredefinedName::NoCopy, .flag = RtAttributeFlagsE::NoCopy},
            {.name = IdentifierManager::PredefinedName::Opaque, .flag = RtAttributeFlagsE::Opaque},
            {.name = IdentifierManager::PredefinedName::NoDoc, .flag = RtAttributeFlagsE::NoDoc},
            {.name = IdentifierManager::PredefinedName::Strict, .flag = RtAttributeFlagsE::Strict},
            {.name = IdentifierManager::PredefinedName::Global, .flag = RtAttributeFlagsE::Global},
            {.name = IdentifierManager::PredefinedName::OperatorIgnore, .flag = RtAttributeFlagsE::OperatorIgnore},
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

    const ConstantValue* unwrapAttributeConstant(Sema& sema, const ConstantValue& value)
    {
        if (!value.isEnumValue())
            return &value;
        return &sema.cstMgr().get(value.getEnumValue());
    }

    Result collectResolvedConstantValue(Sema& sema, const ResolvedCallArgument& arg, const ConstantValue*& outValue)
    {
        outValue = nullptr;
        if (arg.argRef.isValid())
        {
            SWC_RESULT(SemaCheck::isConstant(sema, arg.argRef));
            const SemaNodeView argView = sema.viewConstant(arg.argRef);
            SWC_ASSERT(argView.cst() != nullptr);
            outValue = unwrapAttributeConstant(sema, *argView.cst());
            return Result::Continue;
        }

        if (!arg.defaultCstRef.isValid())
            return Result::Continue;

        outValue = unwrapAttributeConstant(sema, sema.cstMgr().get(arg.defaultCstRef));
        return Result::Continue;
    }

    Result collectResolvedBoolValue(Sema& sema, const ResolvedCallArgument& arg, bool& outValue)
    {
        const ConstantValue* value = nullptr;
        SWC_RESULT(collectResolvedConstantValue(sema, arg, value));
        SWC_ASSERT(value != nullptr);
        SWC_ASSERT(value->isBool());
        outValue = value->getBool();
        return Result::Continue;
    }

    Result collectResolvedEnumMaskValue(Sema& sema, const ResolvedCallArgument& arg, uint64_t& outValue)
    {
        const ConstantValue* value = nullptr;
        SWC_RESULT(collectResolvedConstantValue(sema, arg, value));
        SWC_ASSERT(value != nullptr);
        SWC_ASSERT(value->isInt());
        SWC_ASSERT(value->getInt().fits64());
        outValue = static_cast<uint64_t>(value->getInt().asI64());
        return Result::Continue;
    }

    Result collectSafetyOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(args.size() >= 2);

        uint64_t whatValue = 0;
        bool     enabled   = false;
        SWC_RESULT(collectResolvedEnumMaskValue(sema, args[0], whatValue));
        SWC_RESULT(collectResolvedBoolValue(sema, args[1], enabled));

        outAttributes.addRuntimeSafetyOverride(static_cast<Runtime::SafetyWhat>(whatValue), enabled);
        return Result::Continue;
    }

    Result collectSanityOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(args.size() >= 2);

        uint64_t whatValue = 0;
        bool     enabled   = false;
        SWC_RESULT(collectResolvedEnumMaskValue(sema, args[0], whatValue));
        SWC_RESULT(collectResolvedBoolValue(sema, args[1], enabled));

        outAttributes.addSanityOverride(static_cast<Runtime::SafetyWhat>(whatValue), enabled);
        return Result::Continue;
    }

    Result collectWarningOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(args.size() >= 2);

        const ConstantValue* what = nullptr;
        SWC_RESULT(collectResolvedConstantValue(sema, args[0], what));
        SWC_ASSERT(what != nullptr);
        SWC_ASSERT(what->isString());

        uint64_t levelValue = 0;
        SWC_RESULT(collectResolvedEnumMaskValue(sema, args[1], levelValue));

        const auto                level   = static_cast<WarningLevel>(levelValue);
        const std::optional<Utf8> unknown = outAttributes.warnings.addList(what->getString(), level);
        if (!unknown.has_value())
            return Result::Continue;

        const AstNodeRef errorRef = args[0].argRef.isValid() ? args[0].argRef : sema.curNodeRef();
        auto             diag     = SemaError::report(sema, DiagnosticId::sema_err_unknown_warning, errorRef);
        diag.addArgument(Diagnostic::ARG_VALUE, unknown.value());
        diag.addDidYouMeanNote(Utf8Helper::bestMatch(unknown.value(), WarningPolicy::allIdNames()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result collectBorrowSummaryOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(!args.empty());

        uint64_t returnsMask        = 0;
        uint64_t storesMask         = 0;
        uint64_t intoPairs          = 0;
        uint64_t freesMask          = 0;
        uint64_t reallocatesMask    = 0;
        uint64_t returnsPayloadMask = 0;
        SWC_RESULT(collectResolvedEnumMaskValue(sema, args[0], returnsMask));
        if (args.size() >= 2)
            SWC_RESULT(collectResolvedEnumMaskValue(sema, args[1], storesMask));
        if (args.size() >= 3)
            SWC_RESULT(collectResolvedEnumMaskValue(sema, args[2], intoPairs));
        if (args.size() >= 4)
            SWC_RESULT(collectResolvedEnumMaskValue(sema, args[3], freesMask));
        if (args.size() >= 5)
            SWC_RESULT(collectResolvedEnumMaskValue(sema, args[4], reallocatesMask));
        if (args.size() >= 6)
            SWC_RESULT(collectResolvedEnumMaskValue(sema, args[5], returnsPayloadMask));

        outAttributes.addBorrowSummary(returnsMask, storesMask, intoPairs, freesMask, reallocatesMask, returnsPayloadMask);
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

    Result collectForeignCallConvValue(Sema& sema, CallConvKind& outValue, const ResolvedCallArgument& arg)
    {
        const ConstantValue* value = nullptr;
        SWC_RESULT(collectResolvedConstantValue(sema, arg, value));
        SWC_ASSERT(value != nullptr);
        SWC_ASSERT(value->isInt());
        SWC_ASSERT(value->getInt().fits64());

        const auto callConvKind = static_cast<CallConvKind>(value->getInt().asI64());
        if (!isValidCallConvKind(callConvKind))
            return SemaError::raise(sema, DiagnosticId::sema_err_foreign_invalid_callconv, arg.argRef.isValid() ? arg.argRef : sema.curNodeRef());

        outValue = callConvKind;
        return Result::Continue;
    }

    Result collectForeignOptions(Sema& sema, std::span<const ResolvedCallArgument> args, AttributeList& outAttributes)
    {
        SWC_ASSERT(!args.empty());

        Utf8                        moduleName;
        Utf8                        functionName;
        Utf8                        linkModuleName;
        std::optional<CallConvKind> callConvKind;
        SWC_RESULT(collectForeignStringValue(sema, moduleName, args[0]));
        if (args.size() > 1)
            SWC_RESULT(collectForeignStringValue(sema, functionName, args[1]));
        if (args.size() > 2)
            SWC_RESULT(collectForeignStringValue(sema, linkModuleName, args[2]));
        if (args.size() > 3 && args[3].argRef.isValid())
        {
            auto explicitCallConvKind = CallConvKind::C;
            SWC_RESULT(collectForeignCallConvValue(sema, explicitCallConvKind, args[3]));
            callConvKind = explicitCallConvKind;
        }

        outAttributes.setForeign(moduleName, functionName, linkModuleName, callConvKind);
        return Result::Continue;
    }

    GeneratedOperatorFlags operatorFlagFromName(Sema& sema, std::string_view name)
    {
        struct GeneratedOperatorName
        {
            IdentifierManager::PredefinedName name;
            GeneratedOperatorFlags            flag;
        };

        static constexpr GeneratedOperatorName GENERATED_OPERATOR_NAMES[] = {
            {.name = IdentifierManager::PredefinedName::OpEquals, .flag = GeneratedOperatorFlagsE::OpEquals},
            {.name = IdentifierManager::PredefinedName::OpCompare, .flag = GeneratedOperatorFlagsE::OpCompare},
        };

        const IdentifierManager& idMgr = sema.idMgr();
        for (const auto& mapping : GENERATED_OPERATOR_NAMES)
        {
            if (name == idMgr.get(idMgr.predefined(mapping.name)).name)
                return mapping.flag;
        }

        return GeneratedOperatorFlagsE::Zero;
    }

    Result collectOperatorOptions(Sema& sema, std::span<const AstNodeRef> args, AttributeList& outAttributes)
    {
        for (const AstNodeRef argValueRef : args)
        {
            SWC_RESULT(SemaCheck::isConstant(sema, argValueRef));
            const SemaNodeView argView = sema.viewConstant(argValueRef);
            SWC_ASSERT(argView.cst() != nullptr);
            SWC_ASSERT(argView.cst()->isString());

            const std::string_view       operatorName = argView.cst()->getString();
            const GeneratedOperatorFlags flag         = operatorFlagFromName(sema, operatorName);
            if (flag.none())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_operator_attribute_invalid_operator, argValueRef);
                diag.addArgument(Diagnostic::ARG_VALUE, operatorName);
                diag.report(sema.ctx());
                return Result::Error;
            }

            outAttributes.addGeneratedOperator(flag, sema.node(argValueRef).codeRef());
        }

        return Result::Continue;
    }

    Result normalizeAttributeParamConstantRef(Sema& sema, ConstantRef& ioCstRef, const TypeInfo& paramType, AstNodeRef ownerNodeRef)
    {
        if (!ioCstRef.isValid())
            return Result::Continue;
        if (!paramType.isAnyTypeInfo(sema.ctx()))
            return Result::Continue;
        return SemaHelpers::normalizeTypeInfoConstantRef(sema, ioCstRef, ownerNodeRef);
    }

    Result collectPredefinedAttributeData(Sema& sema, std::span<const AstNodeRef> args, std::span<const ResolvedCallArgument> resolvedArgs, const SymbolFunction& attrSym, AttributeList& outAttributes)
    {
        if (!attrSym.inSwagNamespace(sema.ctx()))
            return Result::Continue;

        const IdentifierManager& idMgr              = sema.idMgr();
        const IdentifierRef      idRef              = attrSym.idRef();
        const IdentifierRef      safetyIdRef        = sema.idMgr().addIdentifier("Safety");
        const IdentifierRef      sanityIdRef        = sema.idMgr().addIdentifier("Sanity");
        const IdentifierRef      borrowSummaryIdRef = sema.idMgr().addIdentifier("BorrowSummary");
        const IdentifierRef      warningIdRef       = sema.idMgr().addIdentifier("Warning");
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Optimize))
            return collectOptimizeLevel(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintMicro))
            return collectPrintMicroOptions(sema, args, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::PrintAst))
            return collectPrintAstOptions(sema, args, outAttributes);
        if (idRef == safetyIdRef)
            return collectSafetyOptions(sema, resolvedArgs, outAttributes);
        if (idRef == sanityIdRef)
            return collectSanityOptions(sema, resolvedArgs, outAttributes);
        if (idRef == borrowSummaryIdRef)
            return collectBorrowSummaryOptions(sema, resolvedArgs, outAttributes);
        if (idRef == warningIdRef)
            return collectWarningOptions(sema, resolvedArgs, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Foreign))
            return collectForeignOptions(sema, resolvedArgs, outAttributes);
        if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::Operators))
            return collectOperatorOptions(sema, args, outAttributes);
        return Result::Continue;
    }

    using AttributeUsageFlags = EnumFlags<Runtime::AttributeUsage>;

    // An enum-typed attribute argument is stored as an 'EnumValue' constant that points at
    // the underlying integer, so reading the raw bits needs one indirection.
    bool attributeParamIntValue(const Sema& sema, ConstantRef cstRef, uint64_t& outValue)
    {
        if (!cstRef.isValid())
            return false;

        const ConstantValue& cst = sema.ctx().cstMgr().get(cstRef);
        if (cst.isEnumValue())
            return attributeParamIntValue(sema, cst.getEnumValue(), outValue);
        if (!cst.isInt())
            return false;

        outValue = cst.getInt().as64();
        return true;
    }

    // The usage an attribute restricts itself to with 'Swag.AttrUsage'. Empty means the
    // attribute declared no restriction, so it is accepted everywhere.
    AttributeUsageFlags declaredAttributeUsage(const Sema& sema, const SymbolFunction& attrSym)
    {
        const IdentifierRef attrUsageIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::AttrUsage);

        AttributeUsageFlags usage;
        for (const AttributeInstance& attribute : attrSym.attributes().attributes)
        {
            if (!attribute.symbol || attribute.symbol->idRef() != attrUsageIdRef || !attribute.symbol->inSwagNamespace(sema.ctx()))
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                uint64_t bits = 0;
                if (attributeParamIntValue(sema, param.valueCstRef, bits))
                    usage.add(static_cast<Runtime::AttributeUsage>(bits));
            }
        }

        return usage;
    }

    bool hasVarDeclFlag(const AstNode& varNode, AstVarDeclFlagsE flag)
    {
        if (varNode.is(AstNodeId::SingleVarDecl))
            return varNode.cast<AstSingleVarDecl>().hasFlag(flag);
        return varNode.cast<AstMultiVarDecl>().hasFlag(flag);
    }

    AttributeUsageFlags variableTargetUsage(const Sema& sema, const AstNode& varNode)
    {
        // 'Variable' means "any variable", so a parameter, a struct field and a global all
        // answer to it on top of their own, narrower kind.
        if (hasVarDeclFlag(varNode, AstVarDeclFlagsE::Parameter))
            return Runtime::AttributeUsage::FunctionParameter | Runtime::AttributeUsage::Variable;
        if (hasVarDeclFlag(varNode, AstVarDeclFlagsE::Const))
            return Runtime::AttributeUsage::Constant;

        const SemaScope& scope = sema.curScope();
        if (scope.isType())
            return Runtime::AttributeUsage::StructVariable | Runtime::AttributeUsage::Variable;
        if (scope.isLocal())
            return Runtime::AttributeUsage::Variable;
        return Runtime::AttributeUsage::GlobalVariable | Runtime::AttributeUsage::Variable;
    }

    // What the attribute list is written on. An empty result means the target is not a kind
    // 'AttrUsage' can name, so nothing is checked. A block is one of those on purpose:
    // attributes on a block are broadcast to the declarations inside, and each of those
    // declarations carries its own list and is checked there.
    AttributeUsageFlags attributeTargetUsage(const Sema& sema, const AstNode& bodyNode)
    {
        switch (bodyNode.id())
        {
            case AstNodeId::FunctionDecl:
                return Runtime::AttributeUsage::Function;
            case AstNodeId::StructDecl:
            case AstNodeId::UnionDecl:
            case AstNodeId::AnonymousStructDecl:
            case AstNodeId::AnonymousUnionDecl:
                return Runtime::AttributeUsage::Struct;
            case AstNodeId::EnumDecl:
                return Runtime::AttributeUsage::Enum;
            case AstNodeId::EnumValue:
                return Runtime::AttributeUsage::EnumValue;
            case AstNodeId::AliasDecl:
                return Runtime::AttributeUsage::Alias;
            case AstNodeId::SingleVarDecl:
            case AstNodeId::MultiVarDecl:
                return variableTargetUsage(sema, bodyNode);
            default:
                return {};
        }
    }

    std::string_view attributeTargetName(AttributeUsageFlags target)
    {
        if (target.has(Runtime::AttributeUsage::Function))
            return "a function";
        if (target.has(Runtime::AttributeUsage::Struct))
            return "a struct";
        if (target.has(Runtime::AttributeUsage::Enum))
            return "an enum";
        if (target.has(Runtime::AttributeUsage::EnumValue))
            return "an enum value";
        if (target.has(Runtime::AttributeUsage::Alias))
            return "an alias";
        if (target.has(Runtime::AttributeUsage::FunctionParameter))
            return "a function parameter";
        if (target.has(Runtime::AttributeUsage::Constant))
            return "a constant";
        if (target.has(Runtime::AttributeUsage::StructVariable))
            return "a struct field";
        if (target.has(Runtime::AttributeUsage::GlobalVariable))
            return "a global variable";
        return "a local variable";
    }

    Result checkAttributeUsage(Sema& sema, AstNodeRef attrRef, AttributeUsageFlags target)
    {
        const AstNode& attrNode = sema.node(attrRef);
        if (!attrNode.is(AstNodeId::Attribute))
            return Result::Continue;

        const Symbol* sym = sema.viewSymbol(attrNode.cast<AstAttribute>().nodeCallRef).sym();
        if (!sym || !sym->isAttribute())
            return Result::Continue;

        const AttributeUsageFlags declared = declaredAttributeUsage(sema, sym->cast<SymbolFunction>());
        if (declared.none() || declared.has(Runtime::AttributeUsage::All) || declared.hasAny(target))
            return Result::Continue;

        // Predefined attributes are written qualified, so name them the way they are used.
        Utf8 displayName;
        if (sym->inSwagNamespace(sema.ctx()))
            displayName.append("Swag.");
        displayName.append(sym->name(sema.ctx()));

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_attribute_usage, attrRef);
        diag.addArgument(Diagnostic::ARG_SYM, displayName);
        diag.addArgument(Diagnostic::ARG_WHAT, attributeTargetName(target));
        diag.addNote(DiagnosticId::sema_note_attribute_declared_usage);
        diag.last().addSpan(sym->codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkAttributeUsages(Sema& sema, const AstAttributeList& list)
    {
        const AttributeUsageFlags target = attributeTargetUsage(sema, sema.node(list.nodeBodyRef));
        if (target.none())
            return Result::Continue;

        const size_t count = sema.ast().spanSize(list.spanChildrenRef);
        for (size_t i = 0; i < count; ++i)
            SWC_RESULT(checkAttributeUsage(sema, sema.ast().nthNode(list.spanChildrenRef, i), target));

        return Result::Continue;
    }

}

Result AstAccessModifier::semaPreDecl(Sema& sema) const
{
    const Token& tok      = sema.token(codeRef());
    const bool   isMember = hasFlag(AstAccessModifierFlagsE::Member);
    SymbolMap*   symMap   = isMember ? SemaFrame::currentSymMap(sema) : nullptr;

    // A bare 'readonly' names no level, so it rides on the one already in effect: the enclosing
    // access block, or the language default when there is none.
    MemberAccessSpec spec   = isMember ? sema.frame().memberAccessFor(symMap) : MemberAccessSpec{};
    SymbolAccess     access = sema.frame().currentAccess();

    switch (tok.id)
    {
        case TokenId::KwdInternal:
            access      = SymbolAccess::Internal;
            spec.access = MemberAccess::Internal;
            break;
        case TokenId::KwdPrivate:
            access      = SymbolAccess::Private;
            spec.access = MemberAccess::Private;
            break;
        case TokenId::KwdPublic:
            access      = SymbolAccess::Public;
            spec.access = MemberAccess::Public;
            break;
        case TokenId::KwdReadOnly:
            break;
        default:
            SWC_UNREACHABLE();
    }

    if (hasFlag(AstAccessModifierFlagsE::ReadOnly))
    {
        // 'private' already withholds every write from outside the declaring type, so 'readonly'
        // on top of it restricts nothing; a spelling that changes nothing hides a misreading.
        if (spec.access == MemberAccess::Private)
        {
            SemaError::report(sema, DiagnosticId::sema_err_readonly_on_private, codeRef()).report(sema.ctx());
            return Result::Error;
        }

        spec.readOnly = true;
    }

    SemaFrame newFrame = sema.frame();
    if (isMember)
        newFrame.setCurrentMemberAccess(spec, symMap);
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

    const auto&  node            = sema.curNode().cast<AstAttributeList>();
    const size_t attributesCount = sema.ast().spanSize(node.spanChildrenRef);
    if (attributesCount)
    {
        const AstNodeRef lastAttributeRef = sema.ast().nthNode(node.spanChildrenRef, attributesCount - 1);
        SemaScope*       attributeScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Zero, lastAttributeRef);
        addSwagUsingAttributeSymMaps(sema, *attributeScope, sema.frame().currentAttributes());
    }

    return Result::Continue;
}

Result AstAttributeList::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (nodeBodyRef.isInvalid())
        return Result::Continue;

    SWC_RESULT(checkAttributeUsages(sema, *this));

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

        // A built-in attribute is recorded as a fast-lookup rt-flag, but it must also stay
        // in the reflected attribute list so user code can query it (Reflection.hasAttribute,
        // getAttributeValue, ...). Fall through to record the attribute instance as well.
        sema.frame().currentAttributes().addRtFlag(attrFlags);
    }

    AttributeInstance inst;
    inst.symbol = &attrSym;

    const auto& params           = attrSym.parameters();
    const bool  hasVariadicParam = !params.empty() && params.back()->type(sema.ctx()).isAnyVariadic();
    for (size_t i = 0; i < resolvedArgs.size(); ++i)
    {
        size_t paramIndex = i;
        if (paramIndex >= params.size())
        {
            SWC_ASSERT(hasVariadicParam);
            paramIndex = params.size() - 1;
        }

        const SymbolVariable* symParam = params[paramIndex];
        SWC_ASSERT(symParam);

        AttributeParamInstance paramInst;
        paramInst.nameIdRef       = symParam->idRef();
        const TypeInfo& paramType = symParam->type(sema.ctx());

        const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
        if (resolvedArg.argRef.isValid())
        {
            const SemaNodeView argView = sema.viewConstant(resolvedArg.argRef);
            paramInst.valueCstRef      = argView.cstRef();
            SWC_RESULT(normalizeAttributeParamConstantRef(sema, paramInst.valueCstRef, paramType, resolvedArg.argRef));
        }
        else if (resolvedArg.defaultCstRef.isValid())
        {
            paramInst.valueCstRef = resolvedArg.defaultCstRef;
            SWC_RESULT(normalizeAttributeParamConstantRef(sema, paramInst.valueCstRef, paramType, nodeCallRef));
        }

        inst.params.push_back(paramInst);
    }

    sema.frame().currentAttributes().attributes.push_back(inst);
    addSwagUsingAttributeSymMaps(sema, sema.curScope(), inst);

    return Result::Continue;
}

SWC_END_NAMESPACE();
