#include "pch.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();
using namespace ModuleApi::Export;

namespace
{
    Utf8 moduleApiSymbolKindName(const Symbol& symbol)
    {
        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            return symbolStruct->isUnion() ? Utf8("union") : Utf8("struct");
        if (symbol.isEnum())
            return "enum";
        if (symbol.isInterface())
            return "interface";
        if (symbol.isAlias())
            return "alias";
        return symbol.toFamily();
    }

    struct ModuleApiValidationScope
    {
        ModuleApiValidationStack* stack = nullptr;

        ModuleApiValidationScope(ModuleApiValidationStack& stack, const Symbol& symbol) :
            stack(&stack)
        {
            this->stack->push(symbol);
        }

        ~ModuleApiValidationScope()
        {
            stack->pop();
        }
    };

    Diagnostic buildModuleApiExportDiagnostic(TaskContext& ctx, DiagnosticId id, const Symbol& symbol)
    {
        Diagnostic diag = Diagnostic::get(id, ctx.compiler().srcView(symbol.srcViewRef()).fileRef());
        diag.last().addSpan(symbol.codeRange(ctx), "", DiagnosticSeverity::Error);
        return diag;
    }

    Result reportModuleApiNonPublicTypeReference(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const Symbol& referencedSymbol)
    {
        Diagnostic diag = buildModuleApiExportDiagnostic(ctx, DiagnosticId::cmd_err_api_public_type_reference_private, focusSymbol);
        diag.addArgument(Diagnostic::ARG_WHAT, moduleApiSymbolKindName(ownerSymbol));
        diag.addArgument(Diagnostic::ARG_SYM, ownerSymbol.name(ctx));
        diag.addArgument(Diagnostic::ARG_VALUE, usage);
        diag.addArgument(Diagnostic::ARG_TYPE, referencedSymbol.getFullScopedName(ctx));
        diag.last().addSpan(referencedSymbol.codeRange(ctx), "referenced type declared here", DiagnosticSeverity::Note);
        diag.report(ctx);
        return Result::Error;
    }

    bool isAnonymousModuleApiTypeSymbol(const Symbol& symbol)
    {
        const auto* symbolStruct = symbol.safeCast<SymbolStruct>();
        if (!symbolStruct || !symbolStruct->decl())
            return false;

        return symbolStruct->decl()->is(AstNodeId::AnonymousStructDecl) || symbolStruct->decl()->is(AstNodeId::AnonymousUnionDecl);
    }

    Result validateTypeReferenceSymbol(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const Symbol& referencedSymbol, ModuleApiValidationStack& stack)
    {
        if (!isCurrentModuleSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (isWholeFileExportedSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (!referencedSymbol.isPublic())
        {
            if (isAnonymousModuleApiTypeSymbol(referencedSymbol))
                return validatePublicTypeSymbol(ctx, referencedSymbol, stack);

            return reportModuleApiNonPublicTypeReference(ctx, ownerSymbol, focusSymbol, usage, referencedSymbol);
        }

        if (referencedSymbol.isAlias() || referencedSymbol.isStruct() || referencedSymbol.isEnum() || referencedSymbol.isInterface())
            return validatePublicTypeSymbol(ctx, referencedSymbol, stack);

        return Result::Continue;
    }

    Result validateExportedTypeRef(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const TypeRef typeRef, ModuleApiValidationStack& stack)
    {
        if (!typeRef.isValid())
            return Result::Continue;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isAlias())
        {
            const SymbolAlias& alias = type.payloadSymAlias();
            SWC_RESULT(validateTypeReferenceSymbol(ctx, ownerSymbol, focusSymbol, usage, alias, stack));
            return validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, alias.underlyingTypeRef(), stack);
        }

        if (type.isStruct())
        {
            const SymbolStruct& symbolStruct = type.payloadSymStruct();
            return validateTypeReferenceSymbol(ctx, ownerSymbol, focusSymbol, usage, symbolStruct, stack);
        }

        if (type.isInterface())
            return validateTypeReferenceSymbol(ctx, ownerSymbol, focusSymbol, usage, type.payloadSymInterface(), stack);

        if (type.isEnum())
            return validateTypeReferenceSymbol(ctx, ownerSymbol, focusSymbol, usage, type.payloadSymEnum(), stack);

        if (type.isArray())
            return validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, type.payloadArrayElemTypeRef(), stack);

        if (type.isSlice() || type.isAnyPointer() || type.isReference() || type.isTypeValue() || type.isTypedVariadic() || type.isCodeBlock())
            return validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, type.payloadTypeRef(), stack);

        if (type.isFunction())
        {
            const SymbolFunction& function = type.payloadSymFunction();
            if (function.returnTypeRef().isValid() && function.returnTypeRef() != ctx.typeMgr().typeVoid())
                SWC_RESULT(validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, function.returnTypeRef(), stack));

            for (const SymbolVariable* param : function.parameters())
            {
                if (!param || !param->typeRef().isValid())
                    continue;
                SWC_RESULT(validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, param->typeRef(), stack));
            }

            return Result::Continue;
        }

        if (type.isAggregateStruct() || type.isAggregateArray())
        {
            for (const TypeRef childTypeRef : type.payloadAggregate().types)
                SWC_RESULT(validateExportedTypeRef(ctx, ownerSymbol, focusSymbol, usage, childTypeRef, stack));
        }

        return Result::Continue;
    }

    Result validatePublicAliasSymbol(TaskContext& ctx, const SymbolAlias& symbolAlias, ModuleApiValidationStack& stack)
    {
        if (const Symbol* aliasedSymbol = symbolAlias.aliasedSymbol())
            SWC_RESULT(validateTypeReferenceSymbol(ctx, symbolAlias, symbolAlias, "its target", *aliasedSymbol, stack));

        if (!symbolAlias.underlyingTypeRef().isValid())
            return Result::Continue;

        return validateExportedTypeRef(ctx, symbolAlias, symbolAlias, "its target", symbolAlias.underlyingTypeRef(), stack);
    }

    Result validatePublicEnumSymbol(TaskContext& ctx, const SymbolEnum& symbolEnum, ModuleApiValidationStack& stack)
    {
        if (!symbolEnum.underlyingTypeRef().isValid())
            return Result::Continue;

        return validateExportedTypeRef(ctx, symbolEnum, symbolEnum, "its underlying type", symbolEnum.underlyingTypeRef(), stack);
    }

    Result validatePublicStructSymbol(TaskContext& ctx, const SymbolStruct& symbolStruct, ModuleApiValidationStack& stack)
    {
        if (isModuleApiOpaqueType(symbolStruct))
            return Result::Continue;

        for (const SymbolVariable* field : symbolStruct.fields())
        {
            if (!field || field->isIgnored())
                continue;

            if (!field->typeRef().isValid())
                continue;

            const Utf8 usage = std::format("field '{}'", field->name(ctx));
            SWC_RESULT(validateExportedTypeRef(ctx, symbolStruct, *field, usage.view(), field->typeRef(), stack));
        }

        return Result::Continue;
    }

    Result validatePublicInterfaceSymbol(TaskContext& ctx, const SymbolInterface& symbolInterface, ModuleApiValidationStack& stack)
    {
        for (const SymbolFunction* function : symbolInterface.functions())
        {
            if (!function)
                continue;

            SWC_RESULT(validatePublicFunctionSymbol(ctx, *function, stack));
        }

        return Result::Continue;
    }

    Result validatePublicFunctionOwner(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack)
    {
        const SymbolImpl* symImpl = symbolFunction.declImplContext();
        if (!symImpl || !symImpl->isForStruct())
            return Result::Continue;

        const SymbolStruct* ownerStruct = symImpl->symStruct();
        if (!ownerStruct)
            return Result::Continue;

        return validateTypeReferenceSymbol(ctx, symbolFunction, symbolFunction, "its owner type", *ownerStruct, stack);
    }
}

namespace ModuleApi::Export
{
    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack)
    {
        if (stack.isValidated(symbol))
            return Result::Continue;
        if (stack.contains(symbol))
            return Result::Continue;

        ModuleApiValidationScope validationScope(stack, symbol);
        auto                     result = Result::Continue;
        if (const auto* symbolAlias = symbol.safeCast<SymbolAlias>())
            result = validatePublicAliasSymbol(ctx, *symbolAlias, stack);
        else if (const auto* symbolEnum = symbol.safeCast<SymbolEnum>())
            result = validatePublicEnumSymbol(ctx, *symbolEnum, stack);
        else if (const auto* symbolInterface = symbol.safeCast<SymbolInterface>())
            result = validatePublicInterfaceSymbol(ctx, *symbolInterface, stack);
        else if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            result = validatePublicStructSymbol(ctx, *symbolStruct, stack);

        SWC_RESULT(result);
        stack.markValidated(symbol);
        return Result::Continue;
    }

    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack)
    {
        if (stack.isValidated(symbolFunction))
            return Result::Continue;
        if (stack.contains(symbolFunction))
            return Result::Continue;

        ModuleApiValidationScope validationScope(stack, symbolFunction);
        SWC_RESULT(validatePublicFunctionOwner(ctx, symbolFunction, stack));

        if (symbolFunction.returnTypeRef().isValid() && symbolFunction.returnTypeRef() != ctx.typeMgr().typeVoid())
            SWC_RESULT(validateExportedTypeRef(ctx, symbolFunction, symbolFunction, "its return type", symbolFunction.returnTypeRef(), stack));

        const auto& parameters = symbolFunction.parameters();
        for (uint32_t i = 0; i < parameters.size(); ++i)
        {
            const SymbolVariable* param = parameters[i];
            if (!param || !param->typeRef().isValid())
                continue;

            Utf8 usage;
            if (param->idRef().isValid())
                usage = std::format("parameter '{}'", param->name(ctx));
            else
                usage = std::format("parameter #{}", i + 1);
            SWC_RESULT(validateExportedTypeRef(ctx, symbolFunction, *param, usage.view(), param->typeRef(), stack));
        }

        stack.markValidated(symbolFunction);
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
