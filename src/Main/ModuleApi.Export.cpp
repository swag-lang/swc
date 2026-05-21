#include "pch.h"
#include "Main/ModuleApi.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool supportsGeneratedModuleApiForeignFunctions(const CompilerInstance& compiler)
    {
        switch (compiler.buildCfg().backendKind)
        {
            case Runtime::BuildCfgBackendKind::StaticLibrary:
            case Runtime::BuildCfgBackendKind::SharedLibrary:
                return true;

            default:
                return false;
        }
    }

    struct ModuleApiFileInfo
    {
        bool legacyExported     = false;
        bool hasModuleNamespace = false;
    };

    struct ModuleApiGeneratedRoot
    {
        const SourceFile*          file    = nullptr;
        AstNodeRef                 nodeRef = AstNodeRef::invalid();
        const Symbol*              symbol  = nullptr;
        std::vector<IdentifierRef> namespacePath;
    };

    struct ModuleApiImplEntry
    {
        Utf8              prefix;
        std::vector<Utf8> snippets;
    };

    struct ModuleApiUsingSnippet
    {
        std::vector<IdentifierRef> namespacePath;
        Utf8                       snippet;
    };

    struct ModuleApiOrderedEntry
    {
        std::vector<IdentifierRef> namespacePath;
        std::vector<Utf8>          snippets;
        Utf8                       implPrefix;
        const SourceFile*          file    = nullptr;
        AstNodeRef                 implRef = AstNodeRef::invalid();
        bool                       isImpl  = false;
    };

    constexpr std::string_view K_GENERATED_API_SPLIT_DIR = "__generated__";

    Utf8 buildCfgString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return Utf8{value};
    }

    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8 moduleNamespaceName = buildCfgString(compiler.buildCfg().moduleNamespace);
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8 artifactName = buildCfgString(compiler.buildCfg().name);
        if (artifactName.empty())
            artifactName = defaultArtifactName(compiler.cmdLine());
        return defaultModuleNamespace(artifactName);
    }

    Utf8 buildModuleArtifactName(const CompilerInstance& compiler)
    {
        Utf8 artifactName = buildCfgString(compiler.buildCfg().name);
        if (!artifactName.empty())
            return artifactName;

        artifactName = defaultArtifactName(compiler.cmdLine());
        if (!artifactName.empty())
            return artifactName;
        return "module";
    }

    bool isCurrentModuleSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        if (!sourceFile)
            return false;

        return sourceFile->hasFlag(FileFlagsE::ModuleSrc) && !sourceFile->isImportedApi();
    }

    bool isModuleApiOpaqueType(const Symbol& symbol)
    {
        return symbol.attributes().hasRtFlag(RtAttributeFlagsE::Opaque);
    }

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

    bool tryGetSwagAttributeIntValue(uint32_t& outValue, TaskContext& ctx, const Symbol& symbol, std::string_view attrName)
    {
        outValue = 0;
        for (const AttributeInstance& attribute : symbol.attributes().attributes)
        {
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != attrName)
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    bool sameNamespacePath(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs)
    {
        return lhs.size() == rhs.size() && std::equal(lhs.begin(), lhs.end(), rhs.begin());
    }

    bool samePublicEntry(const ModuleApiPublicEntry& lhs, const ModuleApiPublicEntry& rhs)
    {
        return lhs.rootRef == rhs.rootRef && sameNamespacePath(lhs.namespacePath, rhs.namespacePath);
    }

    void mergeFileEntry(ModuleApiFileEntry& outEntry, const ModuleApiFileEntry& threadEntry)
    {
        for (const ModuleApiPublicEntry& threadPublicEntry : threadEntry.publicEntries)
        {
            const auto it = std::ranges::find_if(outEntry.publicEntries, [&](const ModuleApiPublicEntry& outPublicEntry) { return samePublicEntry(outPublicEntry, threadPublicEntry); });
            if (it == outEntry.publicEntries.end())
                outEntry.publicEntries.push_back(threadPublicEntry);
        }
    }

    void mergeThreadData(std::unordered_map<SourceViewRef, ModuleApiFileEntry>& outEntries, const ModuleApiPerThreadData& threadData)
    {
        for (const auto& [srcViewRef, threadEntry] : threadData.files)
            mergeFileEntry(outEntries[srcViewRef], threadEntry);
    }

    bool isLegacyExportedFile(const SourceFile& file)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return false;

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, rootNode.cast<AstFile>().spanGlobalsRef);
        if (globalRefs.empty() || globalRefs.front().isInvalid())
            return false;

        const AstNode& globalNode = file.ast().node(globalRefs.front());
        if (globalNode.isNot(AstNodeId::CompilerGlobal))
            return false;

        return globalNode.cast<AstCompilerGlobal>().mode == AstCompilerGlobal::Mode::Export;
    }

    ModuleApiFileInfo analyzeModuleApiFile(const SourceFile& file, std::string_view moduleNamespace)
    {
        ModuleApiFileInfo result;
        const AstNodeRef  rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return result;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return result;

        result.legacyExported = isLegacyExportedFile(file);
        const auto& fileNode  = rootNode.cast<AstFile>();

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, fileNode.spanGlobalsRef);
        for (auto globalRef : globalRefs)
        {
            if (globalRef.isInvalid())
                continue;

            const AstNode& globalNode = file.ast().node(globalRef);
            if (globalNode.isNot(AstNodeId::CompilerGlobal))
                continue;

            const auto& global = globalNode.cast<AstCompilerGlobal>();
            if (global.mode != AstCompilerGlobal::Mode::Namespace)
                continue;

            SmallVector<TokenRef> nameRefs;
            file.ast().appendTokens(nameRefs, global.spanNameRef);
            if (nameRefs.size() != 1)
                continue;

            const std::string_view namespaceName = file.ast().srcView().tokenString(nameRefs[0]);
            if (namespaceName == moduleNamespace)
                result.hasModuleNamespace = true;
        }

        return result;
    }

    bool isLegacyExportedSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && isLegacyExportedFile(*sourceFile);
    }

    std::string_view preferredLineEnding(const SourceFile& file)
    {
        const std::string_view content = file.sourceView();
        if (content.find("\r\n") != std::string_view::npos)
            return "\r\n";
        if (content.find('\n') != std::string_view::npos)
            return "\n";
        return "\r\n";
    }

    uint32_t sourceTokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;

        return token.byteStart;
    }

    uint32_t sourceTokenByteEnd(const SourceView& srcView, const Token& token)
    {
        return sourceTokenByteStart(srcView, token) + token.byteLength;
    }

    bool extractFileNamespacePath(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, std::vector<IdentifierRef>& outNamespacePath)
    {
        outNamespacePath.clear();
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return true;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return true;

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, rootNode.cast<AstFile>().spanGlobalsRef);
        for (const AstNodeRef globalRef : globalRefs)
        {
            if (globalRef.isInvalid())
                continue;

            const AstNode& globalNode = file.ast().node(globalRef);
            if (globalNode.isNot(AstNodeId::CompilerGlobal))
                continue;

            const auto& global = globalNode.cast<AstCompilerGlobal>();
            if (global.mode != AstCompilerGlobal::Mode::Namespace)
                continue;

            SmallVector<TokenRef> nameRefs;
            file.ast().appendTokens(nameRefs, global.spanNameRef);
            for (const TokenRef nameRef : nameRefs)
            {
                if (!nameRef.isValid())
                    continue;

                const std::string_view name = file.ast().srcView().tokenString(nameRef);
                if (name.empty() || name == ".")
                    continue;

                if (outNamespacePath.empty() && name == moduleNamespace)
                    continue;

                outNamespacePath.push_back(ctx.idMgr().addIdentifier(name));
            }

            break;
        }

        return true;
    }

    struct ModuleApiValidationStack
    {
        SmallVector<const Symbol*>        values;
        std::unordered_set<const Symbol*> set;

        bool contains(const Symbol& symbol) const
        {
            return set.contains(&symbol);
        }

        void push(const Symbol& symbol)
        {
            values.push_back(&symbol);
            set.insert(&symbol);
        }

        void pop()
        {
            const Symbol* symbol = values.back();
            values.pop_back();
            set.erase(symbol);
        }
    };

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

    Result reportModuleApiFieldNotPublic(TaskContext& ctx, const SymbolStruct& ownerStruct, const SymbolVariable& field)
    {
        Diagnostic diag = buildModuleApiExportDiagnostic(ctx, DiagnosticId::cmd_err_api_public_type_field_private, field);
        diag.addArgument(Diagnostic::ARG_WHAT, moduleApiSymbolKindName(ownerStruct));
        diag.addArgument(Diagnostic::ARG_SYM, ownerStruct.name(ctx));
        diag.addArgument(Diagnostic::ARG_VALUE, field.name(ctx));
        diag.last().addSpan(ownerStruct.codeRange(ctx), "public type declared here", DiagnosticSeverity::Note);
        diag.report(ctx);
        return Result::Error;
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

    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack);
    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack);
    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, std::string_view eol);
    bool   isModuleApiDeclWrapper(const AstNode& node);

    Result validateTypeReferenceSymbol(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const Symbol& referencedSymbol, ModuleApiValidationStack& stack)
    {
        if (!isCurrentModuleSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (isLegacyExportedSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (!referencedSymbol.isPublic())
            return reportModuleApiNonPublicTypeReference(ctx, ownerSymbol, focusSymbol, usage, referencedSymbol);

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

            if (!field->isPublic())
                return reportModuleApiFieldNotPublic(ctx, symbolStruct, *field);

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

    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack)
    {
        if (stack.contains(symbol))
            return Result::Continue;

        ModuleApiValidationScope validationScope(stack, symbol);
        if (const auto* symbolAlias = symbol.safeCast<SymbolAlias>())
            return validatePublicAliasSymbol(ctx, *symbolAlias, stack);
        if (const auto* symbolEnum = symbol.safeCast<SymbolEnum>())
            return validatePublicEnumSymbol(ctx, *symbolEnum, stack);
        if (const auto* symbolInterface = symbol.safeCast<SymbolInterface>())
            return validatePublicInterfaceSymbol(ctx, *symbolInterface, stack);
        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            return validatePublicStructSymbol(ctx, *symbolStruct, stack);

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

    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack)
    {
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

        return Result::Continue;
    }

    TokenRef moduleApiSnippetStartTokRef(const Ast& ast, const AstNode& node)
    {
        if (node.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> childRefs;
            ast.appendNodes(childRefs, node.cast<AstVarDeclList>().spanChildrenRef);
            if (!childRefs.empty() && childRefs.front().isValid() && ast.hasNode(childRefs.front()))
                return moduleApiSnippetStartTokRef(ast, ast.node(childRefs.front()));
        }

        if (node.is(AstNodeId::AttributeList))
        {
            if (node.tokRef().isValid())
                return node.tokRef();

            const auto& attrList = node.cast<AstAttributeList>();
            if (attrList.nodeBodyRef.isValid() && ast.hasNode(attrList.nodeBodyRef))
                return moduleApiSnippetStartTokRef(ast, ast.node(attrList.nodeBodyRef));
        }

        if (ast.hasSourceView() && node.tokRef().isValid() && node.tokRef().get() > 0)
        {
            const TokenRef prevTokRef(node.tokRef().get() - 1);
            const TokenId  prevId = ast.srcView().token(prevTokRef).id;
            switch (node.id())
            {
                case AstNodeId::FunctionDecl:
                    if (prevId == TokenId::KwdFunc || prevId == TokenId::KwdMtd)
                        return prevTokRef;
                    break;

                case AstNodeId::StructDecl:
                    if (prevId == TokenId::KwdStruct)
                        return prevTokRef;
                    break;

                case AstNodeId::EnumDecl:
                    if (prevId == TokenId::KwdEnum)
                        return prevTokRef;
                    break;

                case AstNodeId::UnionDecl:
                    if (prevId == TokenId::KwdUnion)
                        return prevTokRef;
                    break;

                case AstNodeId::InterfaceDecl:
                    if (prevId == TokenId::KwdInterface)
                        return prevTokRef;
                    break;

                case AstNodeId::AliasDecl:
                    if (prevId == TokenId::KwdAlias)
                        return prevTokRef;
                    break;

                case AstNodeId::Impl:
                    if (prevId == TokenId::KwdImpl)
                        return prevTokRef;
                    break;

                default:
                    break;
            }
        }

        return node.tokRef();
    }

    TokenRef moduleApiFunctionBodyEndTokRef(const Ast& ast, const AstFunctionDecl& functionDecl)
    {
        if (!functionDecl.nodeBodyRef.isValid() || ast.isAdditionalNode(functionDecl.nodeBodyRef))
            return TokenRef::invalid();

        const AstNode& bodyNode        = ast.node(functionDecl.nodeBodyRef);
        TokenRef       bodyStartTokRef = moduleApiSnippetStartTokRef(ast, bodyNode);
        if (!bodyStartTokRef.isValid())
            bodyStartTokRef = bodyNode.tokRef();

        const TokenRef bodyEndTokRef = bodyNode.tokRefEnd(ast);
        if (!bodyEndTokRef.isValid())
            return TokenRef::invalid();

        if (!ast.hasSourceView() || !bodyStartTokRef.isValid())
            return bodyEndTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(bodyStartTokRef).id != TokenId::SymLeftCurly)
            return bodyEndTokRef;

        uint32_t curlyBalance = 0;
        for (uint32_t tokIndex = bodyStartTokRef.get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftCurly)
                curlyBalance++;
            else if (tokenId == TokenId::SymRightCurly)
            {
                SWC_ASSERT(curlyBalance != 0);
                curlyBalance--;
                if (!curlyBalance)
                    return TokenRef(tokIndex);
            }
        }

        return bodyEndTokRef;
    }

    AstNodeRef moduleApiAggregateBodyRef(const AstNode& declNode)
    {
        switch (declNode.id())
        {
            case AstNodeId::StructDecl:
                return declNode.cast<AstStructDecl>().nodeBodyRef;

            case AstNodeId::UnionDecl:
                return declNode.cast<AstUnionDecl>().nodeBodyRef;

            case AstNodeId::EnumDecl:
                return declNode.cast<AstEnumDecl>().nodeBodyRef;

            case AstNodeId::InterfaceDecl:
                return declNode.cast<AstInterfaceDecl>().nodeBodyRef;

            default:
                return AstNodeRef::invalid();
        }
    }

    TokenRef moduleApiAggregateBodyEndTokRef(const Ast& ast, const AstNode& declNode)
    {
        const AstNodeRef bodyRef = moduleApiAggregateBodyRef(declNode);
        if (!bodyRef.isValid() || ast.isAdditionalNode(bodyRef))
            return TokenRef::invalid();

        const AstNode& bodyNode = ast.node(bodyRef);
        if (!bodyNode.tokRef().isValid())
            return TokenRef::invalid();

        const TokenRef bodyEndTokRef = bodyNode.tokRefEnd(ast);
        if (!bodyEndTokRef.isValid())
            return TokenRef::invalid();
        if (!ast.hasSourceView())
            return bodyEndTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(bodyNode.tokRef()).id != TokenId::SymLeftCurly)
            return bodyEndTokRef;

        uint32_t curlyBalance = 0;
        for (uint32_t tokIndex = bodyNode.tokRef().get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftCurly)
                curlyBalance++;
            else if (tokenId == TokenId::SymRightCurly)
            {
                SWC_ASSERT(curlyBalance != 0);
                curlyBalance--;
                if (!curlyBalance)
                    return TokenRef(tokIndex);
            }
        }

        return bodyEndTokRef;
    }

    TokenRef moduleApiSnippetEndTokRef(const Ast& ast, const AstNode& node)
    {
        if (isModuleApiDeclWrapper(node))
        {
            SmallVector<AstNodeRef> childRefs;
            node.collectChildrenFromAst(childRefs, ast);
            for (size_t i = childRefs.size(); i > 0; --i)
            {
                const AstNodeRef childRef = childRefs[i - 1];
                if (!childRef.isValid() || !ast.hasNode(childRef))
                    continue;

                const TokenRef childEndTokRef = moduleApiSnippetEndTokRef(ast, ast.node(childRef));
                if (childEndTokRef.isValid())
                    return childEndTokRef;
            }
        }

        if (const TokenRef bodyEndTokRef = moduleApiAggregateBodyEndTokRef(ast, node); bodyEndTokRef.isValid())
            return bodyEndTokRef;

        if (const auto* functionDecl = node.safeCast<AstFunctionDecl>())
        {
            const TokenRef bodyEndTokRef = moduleApiFunctionBodyEndTokRef(ast, *functionDecl);
            if (bodyEndTokRef.isValid())
                return bodyEndTokRef;
        }

        return node.tokRefEnd(ast);
    }

    bool tryGetModuleApiSnippetStartOffset(const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset);

    struct ModuleApiDelimiterBalance
    {
        uint32_t paren  = 0;
        uint32_t square = 0;
        uint32_t curly  = 0;

        bool empty() const
        {
            return !paren && !square && !curly;
        }
    };

    void updateModuleApiDelimiterBalance(ModuleApiDelimiterBalance& balance, const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::SymLeftParen:
                balance.paren++;
                break;

            case TokenId::SymRightParen:
                if (balance.paren)
                    balance.paren--;
                break;

            case TokenId::SymLeftBracket:
                balance.square++;
                break;

            case TokenId::SymRightBracket:
                if (balance.square)
                    balance.square--;
                break;

            case TokenId::SymLeftCurly:
                balance.curly++;
                break;

            case TokenId::SymRightCurly:
                if (balance.curly)
                    balance.curly--;
                break;

            default:
                break;
        }
    }

    void extendModuleApiSnippetEndOffset(const SourceView& srcView, const TokenRef startTokRef, const TokenRef endTokRef, uint32_t& ioEndOffset)
    {
        ModuleApiDelimiterBalance balance;
        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
            updateModuleApiDelimiterBalance(balance, srcView.token(TokenRef(tokIndex)).id);

        if (balance.empty())
            return;

        for (uint32_t tokIndex = endTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token  = srcView.token(TokenRef(tokIndex));
            bool         extend = false;

            switch (token.id)
            {
                case TokenId::SymRightParen:
                    extend = balance.paren != 0;
                    if (extend)
                        balance.paren--;
                    break;

                case TokenId::SymRightBracket:
                    extend = balance.square != 0;
                    if (extend)
                        balance.square--;
                    break;

                case TokenId::SymRightCurly:
                    extend = balance.curly != 0;
                    if (extend)
                        balance.curly--;
                    break;

                default:
                    return;
            }

            if (!extend)
                return;

            ioEndOffset = sourceTokenByteEnd(srcView, token);
            if (balance.empty())
                return;
        }
    }

    bool tryGetModuleApiSnippetOffsets(const SourceFile& file, const AstNodeRef nodeRef, uint32_t& outStartOffset, uint32_t& outEndOffset)
    {
        outStartOffset = 0;
        outEndOffset   = 0;
        if (nodeRef.isInvalid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        const AstNode& node        = ast.node(nodeRef);
        const TokenRef startTokRef = moduleApiSnippetStartTokRef(ast, node);
        if (!startTokRef.isValid())
            return false;
        const TokenRef endTokRef = moduleApiSnippetEndTokRef(ast, node);
        if (!endTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        outStartOffset            = sourceTokenByteStart(srcView, srcView.token(startTokRef));
        outEndOffset              = sourceTokenByteEnd(srcView, srcView.token(endTokRef));
        extendModuleApiSnippetEndOffset(srcView, startTokRef, endTokRef, outEndOffset);
        return true;
    }

    bool tryGetModuleApiSnippetStartOffset(const SourceFile& file, const AstNodeRef nodeRef, uint32_t& outStartOffset)
    {
        uint32_t endOffset = 0;
        return tryGetModuleApiSnippetOffsets(file, nodeRef, outStartOffset, endOffset);
    }

    bool tryGetModuleApiSnippet(const SourceFile& file, const AstNodeRef nodeRef, std::string_view& outSnippet)
    {
        outSnippet           = {};
        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(file, nodeRef, startOffset, endOffset))
            return false;

        const std::string_view source = file.sourceView();
        endOffset                     = std::min(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset || endOffset > source.size())
            return false;

        outSnippet = source.substr(startOffset, endOffset - startOffset);
        return true;
    }

    struct ModuleApiStripRange
    {
        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
    };

    void collectModuleApiPublicStripRanges(const Ast& ast, const AstNodeRef nodeRef, std::vector<ModuleApiStripRange>& outRanges)
    {
        if (nodeRef.isInvalid() || ast.isAdditionalNode(nodeRef) || !ast.hasSourceView())
            return;

        const AstNode& node = ast.node(nodeRef);
        if (const auto* accessNode = node.safeCast<AstAccessModifier>())
        {
            if (node.tokRef().isValid() && ast.srcView().token(node.tokRef()).id == TokenId::KwdPublic && accessNode->nodeWhatRef.isValid() && ast.hasNode(accessNode->nodeWhatRef))
            {
                const AstNode& childNode        = ast.node(accessNode->nodeWhatRef);
                const TokenRef childStartTokRef = moduleApiSnippetStartTokRef(ast, childNode);
                if (childStartTokRef.isValid())
                {
                    const SourceView& srcView     = ast.srcView();
                    const uint32_t    startOffset = sourceTokenByteStart(srcView, srcView.token(node.tokRef()));
                    const uint32_t    endOffset   = sourceTokenByteStart(srcView, srcView.token(childStartTokRef));
                    if (startOffset < endOffset)
                        outRanges.push_back({startOffset, endOffset});
                }
            }
        }

        SmallVector<AstNodeRef> childRefs;
        node.collectChildrenFromAst(childRefs, ast);
        for (const AstNodeRef childRef : childRefs)
            collectModuleApiPublicStripRanges(ast, childRef, outRanges);
    }

    void normalizeModuleApiStripRanges(std::vector<ModuleApiStripRange>& ioRanges)
    {
        if (ioRanges.empty())
            return;

        std::ranges::sort(ioRanges, [](const ModuleApiStripRange& lhs, const ModuleApiStripRange& rhs) { return lhs.startOffset < rhs.startOffset; });

        size_t writeIndex = 0;
        for (size_t readIndex = 1; readIndex < ioRanges.size(); ++readIndex)
        {
            ModuleApiStripRange&       current = ioRanges[writeIndex];
            const ModuleApiStripRange& next    = ioRanges[readIndex];
            if (next.startOffset <= current.endOffset)
            {
                current.endOffset = std::max(current.endOffset, next.endOffset);
                continue;
            }

            ioRanges[++writeIndex] = next;
        }

        ioRanges.resize(writeIndex + 1);
    }

    Utf8 stripModuleApiSourceRanges(const std::string_view snippetText, const uint32_t snippetStartOffset, std::span<const ModuleApiStripRange> stripRanges)
    {
        if (snippetText.empty() || stripRanges.empty())
            return Utf8{snippetText};

        Utf8     result;
        uint32_t cursor = 0;
        result.reserve(snippetText.size());

        for (const ModuleApiStripRange& range : stripRanges)
        {
            if (range.endOffset <= snippetStartOffset)
                continue;
            if (range.startOffset >= snippetStartOffset + snippetText.size())
                break;

            const uint32_t relativeStart = range.startOffset <= snippetStartOffset ? 0 : range.startOffset - snippetStartOffset;
            const uint32_t relativeEnd   = std::min<uint32_t>(static_cast<uint32_t>(snippetText.size()), range.endOffset - snippetStartOffset);
            if (relativeStart > cursor)
                result.append(snippetText.substr(cursor, relativeStart - cursor));
            cursor = std::max(cursor, relativeEnd);
        }

        if (cursor < snippetText.size())
            result.append(snippetText.substr(cursor));
        return result;
    }

    bool isModuleApiCommentToken(const TokenId tokenId)
    {
        return tokenId == TokenId::CommentLine || tokenId == TokenId::CommentBlock;
    }

    std::string_view moduleApiLeadingIndentPrefix(const SourceFile& file, const uint32_t startOffset)
    {
        const std::string_view source = file.sourceView();
        if (startOffset >= source.size())
            return {};

        uint32_t lineStart = startOffset;
        while (lineStart > 0 && source[lineStart - 1] != '\n' && source[lineStart - 1] != '\r')
            lineStart--;

        uint32_t indentEnd = lineStart;
        while (indentEnd < startOffset && (source[indentEnd] == ' ' || source[indentEnd] == '\t'))
            indentEnd++;

        indentEnd = std::min(indentEnd, startOffset);
        return source.substr(lineStart, indentEnd - lineStart);
    }

    void flushModuleApiLine(Utf8& output, Utf8& line, const std::string_view eol, bool& wroteLine, bool& lineHasContent, const bool forceWrite)
    {
        while (!line.empty() && (line.back() == ' ' || line.back() == '\t'))
            line.pop_back();

        if (forceWrite || lineHasContent)
        {
            if (wroteLine)
                output += eol;
            output += line;
            wroteLine = true;
        }

        line.clear();
        lineHasContent = false;
    }

    struct ModuleApiLexedPiece
    {
        TokenId          tokenId = TokenId::Invalid;
        std::string_view text;
    };

    ModuleApiLexedPiece nextModuleApiLexedPiece(const SourceView& srcView, uint32_t& ioTokenIndex, uint32_t& ioTriviaIndex)
    {
        const auto& tokens = srcView.tokens();
        while (ioTokenIndex < tokens.size())
        {
            const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(TokenRef(ioTokenIndex));
            ioTriviaIndex                       = std::max(ioTriviaIndex, triviaStart);
            if (ioTriviaIndex < triviaEnd)
            {
                const SourceTrivia& trivia = srcView.trivia()[ioTriviaIndex++];
                return {
                    .tokenId = trivia.tok.id,
                    .text    = trivia.tok.string(srcView),
                };
            }

            const Token& token = tokens[ioTokenIndex++];
            if (token.is(TokenId::EndOfFile))
                continue;

            return {
                .tokenId = token.id,
                .text    = token.string(srcView),
            };
        }

        return {};
    }

    void appendModuleApiLexedText(Utf8& output, Utf8& line, const std::string_view text, const std::string_view indentPrefixToStrip, const std::string_view eol, const bool preserveEmptyLine, bool& wroteLine, bool& lineHasContent, bool& pendingSpace, size_t& ioIndentStripIndex)
    {
        size_t index = 0;
        while (index < text.size())
        {
            const char c = text[index];
            if (pendingSpace)
            {
                if (c == '\r' || c == '\n' || c == ' ' || c == '\t')
                {
                    pendingSpace = false;
                }
                else
                {
                    line += ' ';
                    pendingSpace = false;
                }
            }

            if (c == '\r' || c == '\n')
            {
                flushModuleApiLine(output, line, eol, wroteLine, lineHasContent, preserveEmptyLine);
                pendingSpace       = false;
                ioIndentStripIndex = 0;
                if (c == '\r' && index + 1 < text.size() && text[index + 1] == '\n')
                    index++;
                index++;
                continue;
            }

            if (!lineHasContent && ioIndentStripIndex < indentPrefixToStrip.size() && (c == ' ' || c == '\t'))
            {
                if (c == indentPrefixToStrip[ioIndentStripIndex])
                {
                    ioIndentStripIndex++;
                    index++;
                    continue;
                }

                ioIndentStripIndex = indentPrefixToStrip.size();
            }
            else if (!lineHasContent)
            {
                ioIndentStripIndex = indentPrefixToStrip.size();
            }

            line += c;
            if (c != ' ' && c != '\t')
                lineHasContent = true;
            index++;
        }
    }

    Utf8 buildSanitizedModuleApiSnippet(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef, const uint32_t startOffset, const std::string_view snippetText, const std::string_view eol)
    {
        if (snippetText.empty())
            return {};

        const std::string_view indentPrefixToStrip = moduleApiLeadingIndentPrefix(file, startOffset);

        std::vector<ModuleApiStripRange> stripRanges;
        collectModuleApiPublicStripRanges(file.ast(), nodeRef, stripRanges);
        normalizeModuleApiStripRanges(stripRanges);
        const Utf8 filteredSnippet = stripModuleApiSourceRanges(snippetText, startOffset, stripRanges);

        SourceFile lexFile(FileRef::invalid(), file.path(), FileFlagsE::CustomSrc);
        lexFile.setContent(filteredSnippet.view());

        SourceView srcView(SourceViewRef::invalid(), &lexFile);
        Lexer      lexer;
        lexer.tokenize(ctx, srcView, LexerFlagsE::EmitTrivia);

        Utf8     result;
        Utf8     line;
        bool     wroteLine        = false;
        bool     lineHasContent   = false;
        bool     pendingSpace     = false;
        uint32_t tokenIndex       = 0;
        uint32_t triviaIndex      = 0;
        size_t   indentStripIndex = 0;

        result.reserve(filteredSnippet.size());
        line.reserve(filteredSnippet.size());

        while (true)
        {
            const ModuleApiLexedPiece piece = nextModuleApiLexedPiece(srcView, tokenIndex, triviaIndex);
            if (piece.tokenId == TokenId::Invalid)
                break;

            if (isModuleApiCommentToken(piece.tokenId))
            {
                if (!line.empty() && line.back() != ' ' && line.back() != '\t')
                    pendingSpace = true;
                continue;
            }

            if (piece.tokenId == TokenId::Whitespace)
            {
                appendModuleApiLexedText(result, line, piece.text, indentPrefixToStrip, eol, false, wroteLine, lineHasContent, pendingSpace, indentStripIndex);
                continue;
            }

            appendModuleApiLexedText(result, line, piece.text, indentPrefixToStrip, eol, true, wroteLine, lineHasContent, pendingSpace, indentStripIndex);
        }

        flushModuleApiLine(result, line, eol, wroteLine, lineHasContent, false);
        return result;
    }

    AstNodeRef moduleApiOpaqueTypeBodyRef(const AstNode& declNode)
    {
        if (declNode.is(AstNodeId::StructDecl))
            return declNode.cast<AstStructDecl>().nodeBodyRef;
        if (declNode.is(AstNodeId::UnionDecl))
            return declNode.cast<AstUnionDecl>().nodeBodyRef;
        return AstNodeRef::invalid();
    }

    bool tryBuildOpaqueTypePrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        if (!root.file || !root.symbol || !root.symbol->decl())
            return false;

        const AstNode&   declNode = *root.symbol->decl();
        const AstNodeRef bodyRef  = moduleApiOpaqueTypeBodyRef(declNode);
        if (bodyRef.isInvalid())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(*root.file, root.nodeRef, startOffset, endOffset))
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView() || ast.isAdditionalNode(bodyRef))
            return false;

        const AstNode& bodyNode = ast.node(bodyRef);
        if (!bodyNode.tokRef().isValid())
            return false;

        const SourceView&      srcView         = ast.srcView();
        const uint32_t         bodyStartOffset = sourceTokenByteStart(srcView, srcView.token(bodyNode.tokRef()));
        const std::string_view source          = root.file->sourceView();
        if (bodyStartOffset <= startOffset || bodyStartOffset > source.size())
            return false;

        std::string_view prefixText = source.substr(startOffset, bodyStartOffset - startOffset);
        while (!prefixText.empty() && std::isspace(static_cast<unsigned char>(prefixText.back())))
            prefixText.remove_suffix(1);

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, prefixText, eol);
        return !outPrefix.empty();
    }

    Utf8 buildOpaqueTypeSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        const auto* symbolStruct = root.symbol ? root.symbol->safeCast<SymbolStruct>() : nullptr;
        if (!symbolStruct)
            return {};

        Utf8 prefix;
        if (!tryBuildOpaqueTypePrefix(ctx, root, eol, prefix))
        {
            prefix += "#[Swag.Opaque]";
            prefix += eol;
            prefix += symbolStruct->isUnion() ? "union " : "struct ";
            prefix += symbolStruct->name(ctx);
        }

        Utf8     result;
        uint32_t alignValue = 0;
        if (symbolStruct->alignment() > 1 && !tryGetSwagAttributeIntValue(alignValue, ctx, *symbolStruct, "Align"))
        {
            result += std::format("#[Swag.Align({})]", symbolStruct->alignment());
            result += eol;
        }

        result += prefix;
        if (!result.empty() && result.back() != ' ' && result.back() != '\t')
            result += ' ';
        result += "{";
        result += eol;
        result += "    moduleprivate swagOpaqueStorage: [";
        result += std::format("{}", symbolStruct->sizeOf());
        result += "] u8";
        result += eol;
        result += "}";
        return result;
    }

    void trimTrailingModuleApiWhitespace(Utf8& text)
    {
        while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back())))
            text.pop_back();
    }

    void trimTrailingModuleApiDeclarationSeparator(Utf8& text)
    {
        trimTrailingModuleApiWhitespace(text);
        if (!text.empty() && text.back() == ';')
            text.pop_back();
        trimTrailingModuleApiWhitespace(text);
    }

    void prependMissingFunctionAttributes(const SymbolFunction& symbolFunction, const std::string_view eol, Utf8& ioSnippet)
    {
        Utf8       prefix;
        const auto appendAttrIfMissing = [&](const RtAttributeFlagsE flag, std::string_view marker, std::string_view attrText) {
            if (!symbolFunction.attributes().hasRtFlag(flag))
                return;
            if (ioSnippet.contains(marker))
                return;

            prefix += attrText;
            prefix += eol;
        };

        appendAttrIfMissing(RtAttributeFlagsE::Macro, "Macro", "#[Swag.Macro]");
        appendAttrIfMissing(RtAttributeFlagsE::Mixin, "Mixin", "#[Swag.Mixin]");
        appendAttrIfMissing(RtAttributeFlagsE::Inline, "Inline", "#[Swag.Inline]");
        appendAttrIfMissing(RtAttributeFlagsE::ConstExpr, "ConstExpr", "#[Swag.ConstExpr]");
        appendAttrIfMissing(RtAttributeFlagsE::Implicit, "Implicit", "#[Swag.Implicit]");
        if (!prefix.empty())
            ioSnippet = prefix + ioSnippet;
    }

    bool tryFindFunctionBodyStartOffset(const ModuleApiGeneratedRoot& root, uint32_t& outBodyStartOffset)
    {
        outBodyStartOffset         = 0;
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction || !root.file || !symbolFunction->decl())
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView() || root.nodeRef.isInvalid())
            return false;

        const auto* functionDecl = symbolFunction->decl()->safeCast<AstFunctionDecl>();
        if (!functionDecl || !functionDecl->nodeBodyRef.isValid() || ast.isAdditionalNode(functionDecl->nodeBodyRef))
            return false;

        const AstNode& rootNode    = ast.node(root.nodeRef);
        const TokenRef startTokRef = moduleApiSnippetStartTokRef(ast, rootNode);
        if (!startTokRef.isValid())
            return false;

        const AstNode& bodyNode   = ast.node(functionDecl->nodeBodyRef);
        TokenRef       bodyTokRef = moduleApiSnippetStartTokRef(ast, bodyNode);
        if (!bodyTokRef.isValid())
            bodyTokRef = bodyNode.tokRef();
        if (!bodyTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        if (functionDecl->hasFlag(AstFunctionFlagsE::Short))
        {
            for (uint32_t tokIndex = bodyTokRef.get(); tokIndex > startTokRef.get(); --tokIndex)
            {
                const TokenRef arrowTokRef(tokIndex - 1);
                if (srcView.token(arrowTokRef).id != TokenId::SymEqualGreater)
                    continue;

                outBodyStartOffset = sourceTokenByteStart(srcView, srcView.token(arrowTokRef));
                return true;
            }
        }

        outBodyStartOffset = sourceTokenByteStart(srcView, srcView.token(bodyTokRef));
        return true;
    }

    TokenRef moduleApiFunctionParamsEndTokRef(const Ast& ast, const AstFunctionDecl& functionDecl)
    {
        if (!functionDecl.nodeParamsRef.isValid() || ast.isAdditionalNode(functionDecl.nodeParamsRef))
            return TokenRef::invalid();

        const AstNode& paramsNode  = ast.node(functionDecl.nodeParamsRef);
        TokenRef       startTokRef = moduleApiSnippetStartTokRef(ast, paramsNode);
        if (!startTokRef.isValid())
            startTokRef = paramsNode.tokRef();

        const TokenRef endTokRef = paramsNode.tokRefEnd(ast);
        if (!endTokRef.isValid())
            return TokenRef::invalid();
        if (!ast.hasSourceView() || !startTokRef.isValid())
            return endTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(startTokRef).id != TokenId::SymLeftParen)
            return endTokRef;

        uint32_t parenBalance = 0;
        for (uint32_t tokIndex = startTokRef.get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftParen)
                parenBalance++;
            else if (tokenId == TokenId::SymRightParen)
            {
                SWC_ASSERT(parenBalance != 0);
                parenBalance--;
                if (!parenBalance)
                    return TokenRef(tokIndex);
            }
        }

        return endTokRef;
    }

    bool functionDeclPrefixHasExplicitReturnType(const SourceFile& file, const AstFunctionDecl& functionDecl, const uint32_t prefixEndOffset)
    {
        const Ast& ast = file.ast();
        if (!ast.hasSourceView() || !functionDecl.nodeParamsRef.isValid())
            return false;

        const TokenRef paramsEndTokRef = moduleApiFunctionParamsEndTokRef(ast, functionDecl);
        if (!paramsEndTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        for (uint32_t tokIndex = paramsEndTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (sourceTokenByteStart(srcView, token) >= prefixEndOffset)
                break;

            if (token.id == TokenId::SymMinusGreater)
                return true;
        }

        return false;
    }

    bool tryFindFunctionReturnTypeInsertOffset(const SourceFile& file, const AstFunctionDecl& functionDecl, const uint32_t prefixEndOffset, uint32_t& outInsertOffset)
    {
        outInsertOffset = 0;
        const Ast& ast  = file.ast();
        if (!ast.hasSourceView() || !functionDecl.nodeParamsRef.isValid())
            return false;

        const TokenRef paramsEndTokRef = moduleApiFunctionParamsEndTokRef(ast, functionDecl);
        if (!paramsEndTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();

        for (uint32_t tokIndex = paramsEndTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (sourceTokenByteStart(srcView, token) >= prefixEndOffset)
                break;

            switch (token.id)
            {
                case TokenId::SymMinusGreater:
                    outInsertOffset = sourceTokenByteStart(srcView, token);
                    return true;

                case TokenId::KwdThrow:
                case TokenId::KwdWhere:
                case TokenId::KwdVerify:
                case TokenId::SymEqualGreater:
                case TokenId::SymLeftCurly:
                case TokenId::SymSemiColon:
                    outInsertOffset = sourceTokenByteStart(srcView, token);
                    return true;

                default:
                    break;
            }
        }

        outInsertOffset = sourceTokenByteEnd(srcView, srcView.token(paramsEndTokRef));
        return true;
    }

    bool tryBuildFunctionDeclPrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction || !root.file || !symbolFunction->decl())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(*root.file, root.nodeRef, startOffset, endOffset))
            return false;

        if (symbolFunction->decl()->isNot(AstNodeId::FunctionDecl))
            return false;

        uint32_t bodyStartOffset = 0;
        if (tryFindFunctionBodyStartOffset(root, bodyStartOffset))
            endOffset = bodyStartOffset;

        const std::string_view source = root.file->sourceView();
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset)
            return false;

        auto        rawPrefix    = Utf8(source.substr(startOffset, endOffset - startOffset));
        const auto* functionDecl = symbolFunction->decl()->safeCast<AstFunctionDecl>();
        if (functionDecl &&
            symbolFunction->returnTypeRef().isValid() &&
            symbolFunction->returnTypeRef() != ctx.typeMgr().typeVoid() &&
            !functionDeclPrefixHasExplicitReturnType(*root.file, *functionDecl, endOffset))
        {
            uint32_t insertOffset = 0;
            if (tryFindFunctionReturnTypeInsertOffset(*root.file, *functionDecl, endOffset, insertOffset) &&
                insertOffset >= startOffset &&
                insertOffset <= endOffset)
            {
                const Utf8 returnTypeName = ctx.typeMgr().get(symbolFunction->returnTypeRef()).toName(ctx);
                const Utf8 insertion      = std::format("->{} ", returnTypeName.c_str());
                rawPrefix.insert(insertOffset - startOffset, insertion);
            }
        }

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, rawPrefix.view(), eol);
        return !outPrefix.empty();
    }

    Utf8 buildModuleApiForeignAttribute(TaskContext& ctx, const SymbolFunction& symbolFunction, const std::string_view eol)
    {
        std::string_view callConvName = "Swag.CallConv.C";
        switch (symbolFunction.callConvKind())
        {
            case CallConvKind::C:
                callConvName = "Swag.CallConv.C";
                break;
            case CallConvKind::WindowsX64:
                callConvName = "Swag.CallConv.WindowsX64";
                break;
            case CallConvKind::Host:
                callConvName = "Swag.CallConv.Host";
                break;
            default:
                SWC_UNREACHABLE();
        }

        Utf8 result = "#[Swag.Foreign(module: \"";
        result += buildModuleArtifactName(ctx.compiler());
        result += "\", function: \"";
        result += symbolFunction.computePublicApiSymbolName(ctx);
        result += "\", callconv: ";
        result += callConvName;
        result += ")]";
        result += eol;
        return result;
    }

    Utf8 buildFunctionSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction)
            return {};

        Utf8 prefix;
        if (!tryBuildFunctionDeclPrefix(ctx, root, eol, prefix))
            return {};

        prependMissingFunctionAttributes(*symbolFunction, eol, prefix);
        trimTrailingModuleApiDeclarationSeparator(prefix);
        if (prefix.empty())
            return {};

        Utf8 result;
        if (!symbolFunction->isForeign())
            result += buildModuleApiForeignAttribute(ctx, *symbolFunction, eol);

        result += prefix;
        result += ";";
        return result;
    }

    bool tryBuildImplPrefix(TaskContext& ctx, const SourceFile& file, const AstNodeRef implRef, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        if (!implRef.isValid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(file, implRef, startOffset, endOffset))
            return false;

        const AstNode&    implNode    = ast.node(implRef);
        const TokenRef    startTokRef = moduleApiSnippetStartTokRef(ast, implNode);
        const TokenRef    endTokRef   = implNode.tokRefEnd(ast);
        const SourceView& srcView     = ast.srcView();

        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (token.id != TokenId::SymLeftCurly)
                continue;

            endOffset = sourceTokenByteStart(srcView, token);
            break;
        }

        const std::string_view source = file.sourceView();
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return false;

        outPrefix = buildSanitizedModuleApiSnippet(ctx, file, implRef, startOffset, source.substr(startOffset, endOffset - startOffset), eol);
        trimTrailingModuleApiWhitespace(outPrefix);
        return !outPrefix.empty();
    }

    Result buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outSnippet)
    {
        outSnippet.clear();
        if (!root.file)
            return Result::Continue;

        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
        {
            ModuleApiValidationStack validationStack;
            SWC_RESULT(validatePublicFunctionSymbol(ctx, *symbolFunction, validationStack));

            if (symbolFunction->supportsPublicApiForeignExport() && supportsGeneratedModuleApiForeignFunctions(ctx.compiler()))
            {
                outSnippet = buildFunctionSnippet(ctx, root, eol);
                return Result::Continue;
            }

            return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
        }

        if (root.symbol && (root.symbol->isAlias() || root.symbol->isStruct() || root.symbol->isEnum() || root.symbol->isInterface()))
        {
            ModuleApiValidationStack validationStack;
            SWC_RESULT(validatePublicTypeSymbol(ctx, *root.symbol, validationStack));
        }

        if (root.symbol && root.symbol->isStruct() && isModuleApiOpaqueType(*root.symbol))
        {
            if (const auto* symbolStruct = root.symbol->safeCast<SymbolStruct>(); symbolStruct && symbolStruct->isGenericRoot() && !symbolStruct->isGenericInstance())
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

            outSnippet = buildOpaqueTypeSnippet(ctx, root, eol);
            return Result::Continue;
        }

        return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
    }

    bool isModuleApiDeclWrapper(const AstNode& node)
    {
        return node.is(AstNodeId::AccessModifier) ||
               node.is(AstNodeId::AttributeList) ||
               node.is(AstNodeId::VarDeclList);
    }

    bool collectModuleApiNodePath(const Ast& ast, const AstNodeRef currentRef, const AstNodeRef targetRef, SmallVector<AstNodeRef>& ioPath)
    {
        if (!currentRef.isValid() || ast.isAdditionalNode(currentRef))
            return false;

        ioPath.push_back(currentRef);
        if (currentRef == targetRef)
            return true;

        SmallVector<AstNodeRef> childRefs;
        ast.node(currentRef).collectChildrenFromAst(childRefs, ast);
        for (const AstNodeRef childRef : childRefs)
        {
            if (collectModuleApiNodePath(ast, childRef, targetRef, ioPath))
                return true;
        }

        ioPath.pop_back();
        return false;
    }

    AstNodeRef findEnclosingImplRef(const SourceFile& file, const AstNodeRef declRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return AstNodeRef::invalid();

        for (size_t i = 0; i + 1 < nodePath.size(); ++i)
        {
            const AstNodeRef nodeRef = nodePath[i];
            if (file.ast().node(nodeRef).is(AstNodeId::Impl))
                return nodeRef;
        }

        return AstNodeRef::invalid();
    }

    uint32_t moduleApiRootSortByte(const SourceFile& file, const AstNodeRef nodeRef)
    {
        constexpr uint32_t moduleApiInvalidByte = 0xFFFFFFFFu;
        uint32_t           startOffset          = moduleApiInvalidByte;
        if (!tryGetModuleApiSnippetStartOffset(file, nodeRef, startOffset))
            return moduleApiInvalidByte;

        return startOffset;
    }

    void appendGeneratedRootsForFile(const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (fileEntry.publicEntries.empty())
            return;

        std::vector<ModuleApiPublicEntry> sortedEntries = fileEntry.publicEntries;
        std::ranges::stable_sort(sortedEntries, [&](const ModuleApiPublicEntry& lhs, const ModuleApiPublicEntry& rhs) {
            return moduleApiRootSortByte(file, lhs.rootRef) < moduleApiRootSortByte(file, rhs.rootRef);
        });

        for (const ModuleApiPublicEntry& publicEntry : sortedEntries)
            outRoots.push_back({.file = &file, .nodeRef = publicEntry.rootRef, .symbol = publicEntry.symbol, .namespacePath = publicEntry.namespacePath});
    }

    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        outSnippet.clear();
        std::string_view snippetText;
        if (!root.file || !tryGetModuleApiSnippet(*root.file, root.nodeRef, snippetText))
            return Result::Continue;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(*root.file, root.nodeRef, startOffset, endOffset))
            return Result::Continue;

        outSnippet = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, snippetText, eol);
        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
            prependMissingFunctionAttributes(*symbolFunction, eol, outSnippet);
        return Result::Continue;
    }

    fs::path buildGeneratedModuleApiPath(const CompilerInstance& compiler, const fs::path& exportApiDir)
    {
        Utf8 moduleName = defaultArtifactName(compiler.cmdLine());
        if (moduleName.empty())
            moduleName = "module";

        fs::path result = exportApiDir / fs::path(moduleName.c_str());
        result.replace_extension(".swg");
        return result.lexically_normal();
    }

    fs::path buildGeneratedModuleApiSplitDir(const fs::path& exportApiDir)
    {
        return (exportApiDir / fs::path(K_GENERATED_API_SPLIT_DIR)).lexically_normal();
    }

    fs::path buildGeneratedModuleApiSplitPath(const fs::path& exportApiDir, const uint32_t index, const SourceFile& file)
    {
        Utf8 fileName = FileSystem::sanitizeFileName(file.path().filename().string());
        if (fileName.empty())
            fileName = "module";

        fs::path result = buildGeneratedModuleApiSplitDir(exportApiDir) / fs::path(std::format("{:04}-{}", index, fileName.c_str()));
        result.replace_extension(".swg");
        return result.lexically_normal();
    }

    Utf8 buildExportedModuleApiContent(const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace)
    {
        const std::string_view source = file.sourceView();
        if (hasModuleNamespace)
            return Utf8{source};

        uint32_t insertOffset = file.ast().srcView().sourceStartOffset();
        if (file.ast().srcView().numTokens())
        {
            const Token& firstToken = file.ast().srcView().token(TokenRef(0));
            if (firstToken.id != TokenId::EndOfFile)
                insertOffset = firstToken.byteStart;
        }

        insertOffset = std::min<uint32_t>(insertOffset, static_cast<uint32_t>(source.size()));

        Utf8 content;
        content.reserve(source.size() + moduleNamespace.size() + 32);
        content.append(source.substr(0, insertOffset));
        content += "#global namespace ";
        content += moduleNamespace;
        content += preferredLineEnding(file);
        content.append(source.substr(insertOffset));
        return content;
    }

    void appendIndentedSnippet(Utf8& outContent, std::string_view snippetText, std::string_view indent, std::string_view eol)
    {
        size_t pos = 0;
        while (pos < snippetText.size())
        {
            const size_t lineStart = pos;
            size_t       lineEnd   = pos;
            while (lineEnd < snippetText.size() && snippetText[lineEnd] != '\r' && snippetText[lineEnd] != '\n')
                lineEnd++;

            const std::string_view line = snippetText.substr(lineStart, lineEnd - lineStart);
            if (!line.empty())
                outContent += indent;
            outContent.append(line);

            if (lineEnd < snippetText.size())
            {
                outContent += eol;
                pos = lineEnd + 1;
                if (snippetText[lineEnd] == '\r' && pos < snippetText.size() && snippetText[pos] == '\n')
                    pos++;
                continue;
            }

            pos = lineEnd;
        }
    }

    void appendImplEntry(Utf8& outContent, const ModuleApiImplEntry& entry, const Utf8& indent, const std::string_view eol)
    {
        if (entry.prefix.empty())
            return;

        appendIndentedSnippet(outContent, entry.prefix.view(), indent.view(), eol);
        outContent += eol;
        outContent += indent;
        outContent += "{";
        outContent += eol;

        Utf8 childIndent = indent;
        childIndent += "    ";
        for (const Utf8& snippet : entry.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), childIndent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        outContent += indent;
        outContent += "}";
        outContent += eol;
    }

    Result formatGeneratedModuleApiContent(const TaskContext& ctx, Utf8& outContent)
    {
        FormatOptions options;
        options.insertFinalNewline         = true;
        options.trimTrailingNewlines       = true;
        options.preserveTrailingWhitespace = false;

        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(ctx.global(), outContent.view()));
        outContent = formatter.text();
        return Result::Continue;
    }

    fs::path buildGeneratedModuleApiImportPath(const CompilerInstance& compiler, const fs::path& exportApiDir)
    {
        const Utf8 moduleName = buildModuleArtifactName(compiler);
        fs::path   result     = exportApiDir / fs::path(moduleName.c_str());
        result.replace_extension(".deps");
        return result.lexically_normal();
    }

    Utf8 moduleApiImportLocationForExport(const CompilerInstance& compiler, const CompilerInstance::ModuleSetupImport& importRequest)
    {
        if (importRequest.location.empty())
            return {};
        if (importRequest.location == "swag@std")
            return importRequest.location;

        fs::path locationPath{importRequest.location.c_str()};
        if (locationPath.is_relative())
        {
            const fs::path baseDir = compiler.cmdLine().moduleFilePath.parent_path();
            if (!baseDir.empty())
                locationPath = (baseDir / locationPath).lexically_normal();
        }

        return Utf8{FileSystem::normalizePath(locationPath)};
    }

    Result writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content);

    void appendGeneratedModuleImportLine(Utf8& outContent, const CompilerInstance& compiler, const CompilerInstance::ModuleSetupImport& importRequest, const std::string_view eol)
    {
        outContent += "#import(\"";
        outContent += importRequest.moduleName;
        outContent += "\"";

        const Utf8 location = moduleApiImportLocationForExport(compiler, importRequest);
        if (!location.empty())
        {
            outContent += ", location: \"";
            outContent += location;
            outContent += "\"";
        }

        if (!importRequest.version.empty())
        {
            outContent += ", version: \"";
            outContent += importRequest.version;
            outContent += "\"";
        }

        if (importRequest.linkBackendKind != Runtime::BuildCfgBackendKind::None)
        {
            outContent += ", link: \"";
            outContent += backendKindName(importRequest.linkBackendKind);
            outContent += "\"";
        }

        outContent += ")";
        outContent += eol;
    }

    Result writeGeneratedModuleImports(TaskContext& ctx, const fs::path& exportApiDir, std::string_view eol)
    {
        const auto& moduleImports = ctx.compiler().moduleSetupImports();
        if (moduleImports.empty())
            return Result::Continue;

        Utf8 content;
        for (const CompilerInstance::ModuleSetupImport& importRequest : moduleImports)
            appendGeneratedModuleImportLine(content, ctx.compiler(), importRequest, eol);

        SWC_RESULT(formatGeneratedModuleApiContent(ctx, content));
        return writeModuleApiFile(ctx, buildGeneratedModuleApiImportPath(ctx.compiler(), exportApiDir), content.view());
    }

    Result collectFileUsingSnippets(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, std::string_view eol, std::vector<ModuleApiUsingSnippet>& outSnippets)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return Result::Continue;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return Result::Continue;

        std::vector<IdentifierRef> namespacePath;
        extractFileNamespacePath(ctx, file, moduleNamespace, namespacePath);

        SmallVector<AstNodeRef> usingRefs;
        file.ast().appendNodes(usingRefs, rootNode.cast<AstFile>().spanUsingsRef);
        for (const AstNodeRef usingRef : usingRefs)
        {
            if (usingRef.isInvalid())
                continue;

            std::string_view snippetText;
            if (!tryGetModuleApiSnippet(file, usingRef, snippetText))
                continue;

            uint32_t startOffset = 0;
            uint32_t endOffset   = 0;
            if (!tryGetModuleApiSnippetOffsets(file, usingRef, startOffset, endOffset))
                continue;

            Utf8 sanitizedSnippet = buildSanitizedModuleApiSnippet(ctx, file, usingRef, startOffset, snippetText, eol);
            if (sanitizedSnippet.empty())
                continue;

            outSnippets.push_back({.namespacePath = namespacePath, .snippet = std::move(sanitizedSnippet)});
        }

        return Result::Continue;
    }

    Utf8 buildNamespacePathKey(TaskContext& ctx, std::span<const IdentifierRef> namespacePath)
    {
        Utf8 key;
        for (const IdentifierRef idRef : namespacePath)
        {
            key += "::";
            key += ctx.idMgr().get(idRef).name;
        }

        return key;
    }

    uint32_t commonNamespacePrefixCount(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs)
    {
        const uint32_t limit = std::min<uint32_t>(static_cast<uint32_t>(lhs.size()), static_cast<uint32_t>(rhs.size()));
        uint32_t       count = 0;
        while (count < limit && lhs[count] == rhs[count])
            ++count;
        return count;
    }

    Utf8 buildNamespaceIndent(const uint32_t depth)
    {
        Utf8 indent;
        for (uint32_t i = 0; i < depth; ++i)
            indent += "    ";
        return indent;
    }

    void closeNamespaceBlocks(Utf8& outContent, std::span<const IdentifierRef> openNamespacePath, const uint32_t keepCount, std::string_view eol)
    {
        for (uint32_t depth = static_cast<uint32_t>(openNamespacePath.size()); depth > keepCount; --depth)
        {
            const Utf8 indent = buildNamespaceIndent(depth - 1);
            outContent += indent;
            outContent += "}";
            outContent += eol;
        }
    }

    void openNamespaceBlocks(TaskContext& ctx, Utf8& outContent, std::span<const IdentifierRef> namespacePath, const uint32_t fromCount, std::string_view eol)
    {
        for (uint32_t depth = fromCount; depth < namespacePath.size(); ++depth)
        {
            const Utf8 indent = buildNamespaceIndent(depth);
            outContent += indent;
            outContent += "namespace ";
            outContent += ctx.idMgr().get(namespacePath[depth]).name;
            outContent += eol;
            outContent += indent;
            outContent += "{";
            outContent += eol;
        }
    }

    void appendOrderedEntryContent(Utf8& outContent, const ModuleApiOrderedEntry& entry, std::string_view eol)
    {
        const Utf8 indent = buildNamespaceIndent(static_cast<uint32_t>(entry.namespacePath.size()));
        if (entry.isImpl)
        {
            appendImplEntry(outContent, {.prefix = entry.implPrefix, .snippets = entry.snippets}, indent, eol);
            return;
        }

        for (const Utf8& snippet : entry.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), indent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }
    }

    void appendOrderedSnippet(std::vector<ModuleApiOrderedEntry>& outEntries, std::span<const IdentifierRef> namespacePath, Utf8&& snippet)
    {
        if (snippet.empty())
            return;

        if (!outEntries.empty() &&
            !outEntries.back().isImpl &&
            sameNamespacePath(outEntries.back().namespacePath, namespacePath))
        {
            outEntries.back().snippets.push_back(std::move(snippet));
            return;
        }

        ModuleApiOrderedEntry entry;
        entry.namespacePath.assign(namespacePath.begin(), namespacePath.end());
        entry.snippets.push_back(std::move(snippet));
        outEntries.push_back(std::move(entry));
    }

    void appendOrderedImplSnippet(std::vector<ModuleApiOrderedEntry>& outEntries, std::span<const IdentifierRef> namespacePath, const SourceFile& file, AstNodeRef implRef, Utf8&& implPrefix, Utf8&& snippet)
    {
        if (snippet.empty() || implPrefix.empty())
            return;

        if (!outEntries.empty() &&
            outEntries.back().isImpl &&
            outEntries.back().file == &file &&
            outEntries.back().implRef == implRef &&
            outEntries.back().implPrefix == implPrefix &&
            sameNamespacePath(outEntries.back().namespacePath, namespacePath))
        {
            outEntries.back().snippets.push_back(std::move(snippet));
            return;
        }

        ModuleApiOrderedEntry entry;
        entry.namespacePath.assign(namespacePath.begin(), namespacePath.end());
        entry.snippets.push_back(std::move(snippet));
        entry.implPrefix = std::move(implPrefix);
        entry.file       = &file;
        entry.implRef    = implRef;
        entry.isImpl     = true;
        outEntries.push_back(std::move(entry));
    }

    void appendOrderedEntries(TaskContext& ctx, Utf8& outContent, std::span<const ModuleApiOrderedEntry> entries, std::string_view eol)
    {
        std::vector<IdentifierRef> openNamespacePath;
        for (const ModuleApiOrderedEntry& entry : entries)
        {
            const uint32_t sharedCount = commonNamespacePrefixCount(openNamespacePath, entry.namespacePath);
            closeNamespaceBlocks(outContent, openNamespacePath, sharedCount, eol);
            openNamespaceBlocks(ctx, outContent, entry.namespacePath, sharedCount, eol);
            openNamespacePath = entry.namespacePath;
            appendOrderedEntryContent(outContent, entry, eol);
        }

        closeNamespaceBlocks(outContent, openNamespacePath, 0, eol);
    }

    bool tryExtractLeadingNamespacePath(TaskContext& ctx, std::vector<IdentifierRef>& outNamespacePath, std::span<const IdentifierRef> parentNamespacePath, std::string_view snippet)
    {
        constexpr std::string_view namespacePrefix = "namespace ";
        outNamespacePath.clear();
        if (!snippet.starts_with(namespacePrefix))
            return false;

        outNamespacePath.assign(parentNamespacePath.begin(), parentNamespacePath.end());

        std::string_view remaining = snippet.substr(namespacePrefix.size());
        const size_t     bodyPos   = remaining.find_first_of("{\r\n");
        if (bodyPos == std::string_view::npos)
            return false;

        remaining = remaining.substr(0, bodyPos);
        while (!remaining.empty())
        {
            const size_t splitPos = remaining.find('.');
            const auto   name     = splitPos == std::string_view::npos ? remaining : remaining.substr(0, splitPos);
            if (name.empty())
                return false;

            outNamespacePath.push_back(ctx.idMgr().addIdentifier(name));
            if (splitPos == std::string_view::npos)
                break;

            remaining.remove_prefix(splitPos + 1);
        }

        return !outNamespacePath.empty();
    }

    bool appendForwardNamespaceDecls(TaskContext& ctx, Utf8& outContent, std::span<const ModuleApiGeneratedRoot> roots, std::string_view eol)
    {
        bool                     emitted = false;
        std::unordered_set<Utf8> emittedPaths;
        std::vector<IdentifierRef> namespacePath;
        Utf8                     snippet;

        for (const ModuleApiGeneratedRoot& root : roots)
        {
            if (!root.namespacePath.empty())
            {
                const Utf8 pathKey = buildNamespacePathKey(ctx, root.namespacePath);
                if (emittedPaths.insert(pathKey).second)
                {
                    outContent += "namespace ";
                    for (size_t i = 0; i < root.namespacePath.size(); ++i)
                    {
                        if (i)
                            outContent += ".";
                        outContent += ctx.idMgr().get(root.namespacePath[i]).name;
                    }

                    outContent += " {}";
                    outContent += eol;
                    emitted = true;
                }
            }

            if (buildGeneratedRootSnippet(ctx, root, eol, snippet) != Result::Continue || snippet.empty())
                continue;
            if (!tryExtractLeadingNamespacePath(ctx, namespacePath, root.namespacePath, snippet.view()))
                continue;

            const Utf8 pathKey = buildNamespacePathKey(ctx, namespacePath);
            if (!emittedPaths.insert(pathKey).second)
                continue;

            outContent += "namespace ";
            for (size_t i = 0; i < namespacePath.size(); ++i)
            {
                if (i)
                    outContent += ".";
                outContent += ctx.idMgr().get(namespacePath[i]).name;
            }

            outContent += " {}";
            outContent += eol;
            emitted = true;
        }

        return emitted;
    }

    Result buildGeneratedModuleApiContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;
        if (appendForwardNamespaceDecls(ctx, outContent, roots, eol))
            outContent += eol;

        std::vector<ModuleApiOrderedEntry>    orderedEntries;
        std::unordered_set<Utf8>              emittedUsingKeys;
        std::unordered_set<const SourceFile*> usingFiles;

        for (const ModuleApiGeneratedRoot& root : roots)
        {
            if (root.file && usingFiles.insert(root.file).second)
            {
                std::vector<ModuleApiUsingSnippet> usingSnippets;
                SWC_RESULT(collectFileUsingSnippets(ctx, *root.file, moduleNamespace, eol, usingSnippets));
                for (ModuleApiUsingSnippet& usingSnippet : usingSnippets)
                {
                    Utf8 usingKey = buildNamespacePathKey(ctx, usingSnippet.namespacePath);
                    usingKey += '\n';
                    usingKey += usingSnippet.snippet;
                    if (!emittedUsingKeys.insert(usingKey).second)
                        continue;

                    appendOrderedSnippet(orderedEntries, usingSnippet.namespacePath, std::move(usingSnippet.snippet));
                }
            }

            Utf8 sanitizedSnippet;
            SWC_RESULT(buildGeneratedRootSnippet(ctx, root, eol, sanitizedSnippet));
            if (sanitizedSnippet.empty())
                continue;

            const AstNodeRef implRef = root.file ? findEnclosingImplRef(*root.file, root.nodeRef) : AstNodeRef::invalid();
            if (root.file && implRef.isValid())
            {
                Utf8 implPrefix;
                if (tryBuildImplPrefix(ctx, *root.file, implRef, eol, implPrefix))
                {
                    appendOrderedImplSnippet(orderedEntries, root.namespacePath, *root.file, implRef, std::move(implPrefix), std::move(sanitizedSnippet));
                    continue;
                }
            }

            appendOrderedSnippet(orderedEntries, root.namespacePath, std::move(sanitizedSnippet));
        }

        appendOrderedEntries(ctx, outContent, orderedEntries, eol);

        if (roots.empty() && outContent.back() != '\n' && outContent.back() != '\r')
            outContent += eol;

        return formatGeneratedModuleApiContent(ctx, outContent);
    }

    Result writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(dstPath, content.data(), content.size(), ioError) == Result::Continue)
            return Result::Continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, dstPath, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    Result ensureModuleApiDirectory(TaskContext& ctx, const fs::path& path)
    {
        if (path.empty())
            return Result::Continue;

        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_dir_create_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        return Result::Continue;
    }

    Result writeGeneratedModuleApiSplitFiles(TaskContext& ctx, const fs::path& exportApiDir, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol)
    {
        if (roots.empty())
            return Result::Continue;

        const fs::path splitDir = buildGeneratedModuleApiSplitDir(exportApiDir);
        SWC_RESULT(ensureModuleApiDirectory(ctx, splitDir));

        uint32_t fileIndex = 0;
        size_t   rootIndex = 0;
        while (rootIndex < roots.size())
        {
            const SourceFile* sourceFile = roots[rootIndex].file;
            size_t            nextIndex  = rootIndex + 1;
            while (nextIndex < roots.size() && roots[nextIndex].file == sourceFile)
                ++nextIndex;

            if (sourceFile)
            {
                Utf8 content;
                SWC_RESULT(buildGeneratedModuleApiContent(ctx, roots.subspan(rootIndex, nextIndex - rootIndex), moduleNamespace, eol, content));
                if (!content.empty())
                    SWC_RESULT(writeModuleApiFile(ctx, buildGeneratedModuleApiSplitPath(exportApiDir, fileIndex, *sourceFile), content.view()));
            }

            fileIndex++;
            rootIndex = nextIndex;
        }

        return Result::Continue;
    }

    Result reportInvalidFolder(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }
}

namespace ModuleApi
{
    Result exportFiles(TaskContext& ctx)
    {
        CompilerInstance& compiler     = ctx.compiler();
        const fs::path&   exportApiDir = compiler.cmdLine().exportApiDir;
        if (exportApiDir.empty())
            return Result::Continue;

        std::unordered_map<SourceViewRef, ModuleApiFileEntry> collectedEntries;
        for (size_t i = 0; i < compiler.numPerThreadData(); ++i)
            mergeThreadData(collectedEntries, compiler.moduleApiPerThreadData(i));

        const Utf8                          moduleNamespace  = buildModuleNamespaceName(compiler);
        const SourceFile*                   firstSourceFile  = nullptr;
        bool                                hasModuleSources = false;
        std::vector<ModuleApiGeneratedRoot> generatedRoots;

        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
                continue;

            hasModuleSources = true;
            if (!firstSourceFile)
                firstSourceFile = file;

            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (fileInfo.legacyExported)
                continue;

            const auto fileEntryIt = collectedEntries.find(file->ast().srcView().ref());
            if (fileEntryIt == collectedEntries.end())
                continue;
            const ModuleApiFileEntry& fileEntry = fileEntryIt->second;

            appendGeneratedRootsForFile(*file, fileEntry, generatedRoots);
        }

        if (!hasModuleSources)
            return Result::Continue;

        SWC_RESULT(ensureModuleApiDirectory(ctx, exportApiDir));
        SWC_RESULT(FileSystem::clearDirectoryContents(ctx, exportApiDir, DiagnosticId::cmd_err_api_dir_clear_failed));

        std::unordered_map<Utf8, fs::path> exportedFileNames;
        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
                continue;

            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (!fileInfo.legacyExported)
                continue;

            const fs::path dstPath  = (exportApiDir / file->path().filename()).lexically_normal();
            const Utf8     fileName = dstPath.filename().string();
            const auto     inserted = exportedFileNames.emplace(fileName, file->path());
            if (!inserted.second)
            {
                const Utf8 because = std::format("duplicate exported API file name from '{}' and '{}'", inserted.first->second.string(), file->path().string());
                return reportInvalidFolder(ctx, dstPath, because);
            }

            const Utf8 content = buildExportedModuleApiContent(*file, moduleNamespace.view(), fileInfo.hasModuleNamespace);
            if (writeModuleApiFile(ctx, dstPath, content.view()) != Result::Continue)
                return Result::Error;
        }

        if (!firstSourceFile)
            return Result::Continue;

        SWC_RESULT(writeGeneratedModuleImports(ctx, exportApiDir, preferredLineEnding(*firstSourceFile)));

        const fs::path generatedDstPath  = buildGeneratedModuleApiPath(compiler, exportApiDir);
        const Utf8     generatedFileName = generatedDstPath.filename().string();
        if (exportedFileNames.contains(generatedFileName))
            return Result::Continue;

        SWC_RESULT(writeGeneratedModuleApiSplitFiles(ctx, exportApiDir, generatedRoots, moduleNamespace.view(), preferredLineEnding(*firstSourceFile)));

        Utf8 content;
        SWC_RESULT(buildGeneratedModuleApiContent(ctx, generatedRoots, moduleNamespace.view(), preferredLineEnding(*firstSourceFile), content));
        if (writeModuleApiFile(ctx, generatedDstPath, content.view()) != Result::Continue)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
