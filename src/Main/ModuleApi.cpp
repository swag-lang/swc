#include "pch.h"
#include "Main/ModuleApi.h"
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
        const SourceFile*               file    = nullptr;
        AstNodeRef                      nodeRef = AstNodeRef::invalid();
        const Symbol*                   symbol  = nullptr;
        std::vector<IdentifierRef>      namespacePath;
    };

    struct ModuleApiNamespaceNode
    {
        struct ImplNode
        {
            const SourceFile*  file    = nullptr;
            AstNodeRef         implRef = AstNodeRef::invalid();
            Utf8               prefix;
            std::vector<Utf8>  snippets;
        };

        IdentifierRef                idRef = IdentifierRef::invalid();
        std::vector<Utf8>            snippets;
        std::vector<ImplNode>        impls;
        std::vector<ModuleApiNamespaceNode> children;
    };

    const SourceFile* sourceFileFromRef(const CompilerInstance& compiler, const SourceViewRef srcViewRef)
    {
        if (!srcViewRef.isValid())
            return nullptr;

        const SourceView& srcView = compiler.srcView(srcViewRef);
        return srcView.file();
    }

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

    const SourceFile* sourceFileFromSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        return sourceFileFromRef(compiler, symbol.srcViewRef());
    }

    bool isCurrentModuleSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        const SourceFile* sourceFile = sourceFileFromSymbol(compiler, symbol);
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

    bool isSupportedPublicDeclSymbol(const Symbol& symbol)
    {
        if (!symbol.decl())
            return false;

        if (symbol.isConstant())
            return symbol.decl()->is(AstNodeId::SingleVarDecl) || symbol.decl()->is(AstNodeId::MultiVarDecl);

        if (const auto* symbolAlias = symbol.safeCast<SymbolAlias>())
            return symbolAlias->decl()->is(AstNodeId::AliasDecl);

        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
        {
            if (symbolStruct->isGenericInstance())
                return false;

            return symbolStruct->decl()->is(AstNodeId::StructDecl) || symbolStruct->decl()->is(AstNodeId::UnionDecl);
        }

        if (const auto* symbolFunction = symbol.safeCast<SymbolFunction>())
        {
            return symbolFunction->supportsGeneratedModuleApiExport();
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

    void recordPublicEntry(ModuleApiPerThreadData& state, const SourceViewRef srcViewRef, const ModuleApiPublicEntry& publicEntry)
    {
        if (!srcViewRef.isValid() || publicEntry.rootRef.isInvalid())
            return;

        ModuleApiFileEntry& entry = state.files[srcViewRef];
        const auto          it    = std::ranges::find_if(entry.publicEntries, [&](const ModuleApiPublicEntry& candidate) { return samePublicEntry(candidate, publicEntry); });
        if (it == entry.publicEntries.end())
            entry.publicEntries.push_back(publicEntry);
        else if (!it->symbol)
            it->symbol = publicEntry.symbol;
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
        const auto& fileNode = rootNode.cast<AstFile>();

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, fileNode.spanGlobalsRef);
        for (uint32_t i = 0; i < globalRefs.size(); ++i)
        {
            const AstNodeRef globalRef = globalRefs[i];
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
        const SourceFile* sourceFile = sourceFileFromSymbol(compiler, symbol);
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

    bool moduleApiValidationStackContains(std::span<const Symbol*> stack, const Symbol& symbol)
    {
        return std::ranges::find(stack, &symbol) != stack.end();
    }

    struct ModuleApiValidationScope
    {
        SmallVector<const Symbol*>& stack;

        ModuleApiValidationScope(SmallVector<const Symbol*>& stack, const Symbol& symbol) :
            stack(stack)
        {
            stack.push_back(&symbol);
        }

        ~ModuleApiValidationScope()
        {
            stack.pop_back();
        }
    };

    Result reportModuleApiFieldNotPublic(TaskContext& ctx, const SymbolStruct& ownerStruct, const SymbolVariable& field)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_public_type_field_private, ctx.compiler().srcView(field.srcViewRef()).fileRef());
        diag.addArgument(Diagnostic::ARG_WHAT, moduleApiSymbolKindName(ownerStruct));
        diag.addArgument(Diagnostic::ARG_SYM, ownerStruct.name(ctx));
        diag.addArgument(Diagnostic::ARG_VALUE, field.name(ctx));
        diag.last().addSpan(field.codeRange(ctx), "", DiagnosticSeverity::Error);
        diag.last().addSpan(ownerStruct.codeRange(ctx), "public type declared here", DiagnosticSeverity::Note);
        diag.report(ctx);
        return Result::Error;
    }

    Result reportModuleApiNonPublicTypeReference(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const Symbol& referencedSymbol)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_public_type_reference_private, ctx.compiler().srcView(focusSymbol.srcViewRef()).fileRef());
        diag.addArgument(Diagnostic::ARG_WHAT, moduleApiSymbolKindName(ownerSymbol));
        diag.addArgument(Diagnostic::ARG_SYM, ownerSymbol.name(ctx));
        diag.addArgument(Diagnostic::ARG_VALUE, usage);
        diag.addArgument(Diagnostic::ARG_TYPE, referencedSymbol.getFullScopedName(ctx));
        diag.last().addSpan(focusSymbol.codeRange(ctx), "", DiagnosticSeverity::Error);
        diag.last().addSpan(referencedSymbol.codeRange(ctx), "referenced type declared here", DiagnosticSeverity::Note);
        diag.report(ctx);
        return Result::Error;
    }

    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, SmallVector<const Symbol*>& stack);
    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, SmallVector<const Symbol*>& stack);
    bool   isModuleApiDeclWrapper(const AstNode& node);

    Result validateTypeReferenceSymbol(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const Symbol& referencedSymbol, SmallVector<const Symbol*>& stack)
    {
        if (!isCurrentModuleSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (isLegacyExportedSymbol(ctx.compiler(), referencedSymbol))
            return Result::Continue;

        if (!referencedSymbol.isPublic())
            return reportModuleApiNonPublicTypeReference(ctx, ownerSymbol, focusSymbol, usage, referencedSymbol);

        if (referencedSymbol.isAlias() || referencedSymbol.isStruct())
            return validatePublicTypeSymbol(ctx, referencedSymbol, stack);

        return Result::Continue;
    }

    Result validateExportedTypeRef(TaskContext& ctx, const Symbol& ownerSymbol, const Symbol& focusSymbol, std::string_view usage, const TypeRef typeRef, SmallVector<const Symbol*>& stack)
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

    Result validatePublicAliasSymbol(TaskContext& ctx, const SymbolAlias& symbolAlias, SmallVector<const Symbol*>& stack)
    {
        if (const Symbol* aliasedSymbol = symbolAlias.aliasedSymbol())
            SWC_RESULT(validateTypeReferenceSymbol(ctx, symbolAlias, symbolAlias, "its target", *aliasedSymbol, stack));

        if (!symbolAlias.underlyingTypeRef().isValid())
            return Result::Continue;

        return validateExportedTypeRef(ctx, symbolAlias, symbolAlias, "its target", symbolAlias.underlyingTypeRef(), stack);
    }

    Result validatePublicStructSymbol(TaskContext& ctx, const SymbolStruct& symbolStruct, SmallVector<const Symbol*>& stack)
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

    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, SmallVector<const Symbol*>& stack)
    {
        if (moduleApiValidationStackContains(stack.span(), symbol))
            return Result::Continue;

        ModuleApiValidationScope validationScope(stack, symbol);
        if (const auto* symbolAlias = symbol.safeCast<SymbolAlias>())
            return validatePublicAliasSymbol(ctx, *symbolAlias, stack);
        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            return validatePublicStructSymbol(ctx, *symbolStruct, stack);

        return Result::Continue;
    }

    Result validatePublicFunctionOwner(TaskContext& ctx, const SymbolFunction& symbolFunction, SmallVector<const Symbol*>& stack)
    {
        const SymbolImpl* symImpl = symbolFunction.declImplContext();
        if (!symImpl || !symImpl->isForStruct())
            return Result::Continue;

        const SymbolStruct* ownerStruct = symImpl->symStruct();
        if (!ownerStruct)
            return Result::Continue;

        return validateTypeReferenceSymbol(ctx, symbolFunction, symbolFunction, "its owner type", *ownerStruct, stack);
    }

    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, SmallVector<const Symbol*>& stack)
    {
        if (moduleApiValidationStackContains(stack.span(), symbolFunction))
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

        const AstNode& bodyNode = ast.node(functionDecl.nodeBodyRef);
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

        if (const auto* functionDecl = node.safeCast<AstFunctionDecl>())
        {
            const TokenRef bodyEndTokRef = moduleApiFunctionBodyEndTokRef(ast, *functionDecl);
            if (bodyEndTokRef.isValid())
                return bodyEndTokRef;
        }

        return node.tokRefEnd(ast);
    }

    bool tryGetModuleApiSnippetStartOffset(const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset);

    constexpr uint32_t moduleApiInvalidByte = 0xFFFFFFFFu;

    uint32_t moduleApiNodeSortByte(const Ast& ast, const SourceView& srcView, const AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || ast.isAdditionalNode(nodeRef))
            return moduleApiInvalidByte;

        const AstNode& node = ast.node(nodeRef);
        if (const TokenRef tokRef = node.tokRef(); tokRef.isValid())
        {
            const Token& tok = srcView.token(tokRef);
            if (tok.isNot(TokenId::EndOfFile))
                return sourceTokenByteStart(srcView, tok);
        }

        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(node.id()).collectChildren(children, ast, node);

        uint32_t result = moduleApiInvalidByte;
        for (const AstNodeRef childRef : children)
            result = std::min(result, moduleApiNodeSortByte(ast, srcView, childRef));
        return result;
    }

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
            const Token& token = srcView.token(TokenRef(tokIndex));
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
        outStartOffset = sourceTokenByteStart(srcView, srcView.token(startTokRef));
        outEndOffset   = sourceTokenByteEnd(srcView, srcView.token(endTokRef));
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
        outSnippet = {};
        uint32_t   startOffset = 0;
        uint32_t   endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(file, nodeRef, startOffset, endOffset))
            return false;

        const std::string_view source = file.sourceView();
        endOffset = std::min(endOffset, static_cast<uint32_t>(source.size()));
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

        if (indentEnd > startOffset)
            indentEnd = startOffset;
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
                pendingSpace = false;
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

        const std::string_view source      = file.sourceView();
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
        bool     wroteLine      = false;
        bool     lineHasContent = false;
        bool     pendingSpace   = false;
        uint32_t tokenIndex     = 0;
        uint32_t triviaIndex    = 0;
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

        const AstNode& declNode = *root.symbol->decl();
        const AstNodeRef bodyRef = moduleApiOpaqueTypeBodyRef(declNode);
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

        const SourceView& srcView         = ast.srcView();
        const uint32_t    bodyStartOffset = sourceTokenByteStart(srcView, srcView.token(bodyNode.tokRef()));
        const std::string_view source     = root.file->sourceView();
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

        Utf8 result;
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

    bool tryFindFunctionBodyStartOffset(const ModuleApiGeneratedRoot& root, uint32_t& outBodyStartOffset)
    {
        outBodyStartOffset = 0;
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

        const AstNode& bodyNode = ast.node(functionDecl->nodeBodyRef);
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
        endOffset = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset)
            return false;

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, source.substr(startOffset, endOffset - startOffset), eol);
        return !outPrefix.empty();
    }

    Utf8 buildModuleApiForeignAttribute(TaskContext& ctx, const SymbolFunction& symbolFunction, const std::string_view eol)
    {
        Utf8 result = "#[Swag.Foreign(\"";
        result += buildModuleArtifactName(ctx.compiler());
        result += "\", \"";
        result += symbolFunction.computePublicApiSymbolName(ctx);
        result += "\")]";
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

    bool tryBuildImplPrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        const SymbolImpl* symImpl = symbolFunction ? symbolFunction->declImplContext() : nullptr;
        if (!symbolFunction || !symImpl || !root.file || !symImpl->decl())
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView())
            return false;

        const AstNodeRef implRef = symImpl->decl()->nodeRef(ast);
        if (implRef.isInvalid())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(*root.file, implRef, startOffset, endOffset))
            return false;

        const AstNode&   implNode = *symImpl->decl();
        const TokenRef   startTokRef = moduleApiSnippetStartTokRef(ast, implNode);
        const TokenRef   endTokRef = implNode.tokRefEnd(ast);
        const SourceView& srcView = ast.srcView();

        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (token.id != TokenId::SymLeftCurly)
                continue;

            endOffset = sourceTokenByteStart(srcView, token);
            break;
        }

        const std::string_view source = root.file->sourceView();
        endOffset = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return false;

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, source.substr(startOffset, endOffset - startOffset), eol);
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
            if (symbolFunction->supportsPublicApiForeignExport())
            {
                if (!supportsGeneratedModuleApiForeignFunctions(ctx.compiler()))
                    return Result::Continue;

                SmallVector<const Symbol*> validationStack;
                SWC_RESULT(validatePublicFunctionSymbol(ctx, *symbolFunction, validationStack));
                outSnippet = buildFunctionSnippet(ctx, root, eol);
                return Result::Continue;
            }

            if (symbolFunction->attributes().hasRtFlag(RtAttributeFlagsE::Macro) || symbolFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            {
                std::string_view snippetText;
                if (!tryGetModuleApiSnippet(*root.file, root.nodeRef, snippetText))
                    return Result::Continue;

                uint32_t startOffset = 0;
                uint32_t endOffset   = 0;
                if (!tryGetModuleApiSnippetOffsets(*root.file, root.nodeRef, startOffset, endOffset))
                    return Result::Continue;

                outSnippet = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, snippetText, eol);
            }

            return Result::Continue;
        }

        if (root.symbol && (root.symbol->isAlias() || root.symbol->isStruct()))
        {
            SmallVector<const Symbol*> validationStack;
            SWC_RESULT(validatePublicTypeSymbol(ctx, *root.symbol, validationStack));
        }

        if (root.symbol && root.symbol->isStruct() && isModuleApiOpaqueType(*root.symbol))
        {
            outSnippet = buildOpaqueTypeSnippet(ctx, root, eol);
            return Result::Continue;
        }

        std::string_view snippetText;
        if (!tryGetModuleApiSnippet(*root.file, root.nodeRef, snippetText))
            return Result::Continue;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(*root.file, root.nodeRef, startOffset, endOffset))
            return Result::Continue;

        outSnippet = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, snippetText, eol);
        return Result::Continue;
    }

    bool isModuleApiDeclWrapper(const AstNode& node)
    {
        return node.is(AstNodeId::AccessModifier) ||
               node.is(AstNodeId::AttributeList) ||
               node.is(AstNodeId::VarDeclList);
    }

    bool isModuleApiForbiddenContainer(const AstNode& node)
    {
        return node.is(AstNodeId::FunctionDecl) ||
               node.is(AstNodeId::StructDecl) ||
               node.is(AstNodeId::EnumDecl) ||
               node.is(AstNodeId::InterfaceDecl) ||
               node.is(AstNodeId::Impl);
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

    AstNodeRef findExportDeclRoot(const SourceFile& file, const AstNodeRef declRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return AstNodeRef::invalid();

        AstNodeRef exportRootRef = declRef;
        for (size_t i = nodePath.size(); i > 1; --i)
        {
            const AstNodeRef parentRef = nodePath[i - 2];
            const AstNode&   parent    = file.ast().node(parentRef);
            if (!isModuleApiDeclWrapper(parent))
                break;

            exportRootRef = parentRef;
        }

        return exportRootRef;
    }

    bool isExportedPublicDeclScope(const SourceFile& file, const AstNodeRef declRef, const Symbol& symbol)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return false;

        for (size_t i = 0; i + 1 < nodePath.size(); ++i)
        {
            const AstNode& node = file.ast().node(nodePath[i]);
            if (node.is(AstNodeId::Impl))
            {
                if (symbol.isFunction())
                    continue;
                return false;
            }

            if (isModuleApiForbiddenContainer(node))
                return false;
        }

        return true;
    }

    bool extractPublicNamespacePath(const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath)
    {
        outNamespacePath.clear();

        const SymbolMap* symMap = symbol.ownerSymMap();
        while (symMap)
        {
            if (symMap->isModule())
                break;

            if (symMap->isImpl() || symMap->isStruct() || symMap->isEnum() || symMap->isInterface())
            {
                symMap = symMap->ownerSymMap();
                continue;
            }

            if (!symMap->isNamespace())
                return false;

            const SymbolMap* ownerSymMap = symMap->ownerSymMap();
            if (ownerSymMap && ownerSymMap->isModule())
            {
                symMap = ownerSymMap;
                continue;
            }

            if (symMap->idRef().isValid())
                outNamespacePath.push_back(symMap->idRef());

            symMap = ownerSymMap;
        }

        std::ranges::reverse(outNamespacePath);
        return true;
    }

    uint32_t moduleApiRootSortByte(const SourceFile& file, const AstNodeRef nodeRef)
    {
        uint32_t startOffset = moduleApiInvalidByte;
        if (!tryGetModuleApiSnippetStartOffset(file, nodeRef, startOffset))
            return moduleApiInvalidByte;

        return startOffset;
    }

    void appendGeneratedRootsForFile(const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (fileEntry.publicEntries.empty())
            return;

        std::vector<ModuleApiPublicEntry> sortedEntries = fileEntry.publicEntries;
        std::ranges::stable_sort(sortedEntries, [&](const ModuleApiPublicEntry& lhs, const ModuleApiPublicEntry& rhs)
        {
            return moduleApiRootSortByte(file, lhs.rootRef) < moduleApiRootSortByte(file, rhs.rootRef);
        });

        for (const ModuleApiPublicEntry& publicEntry : sortedEntries)
            outRoots.push_back({.file = &file, .nodeRef = publicEntry.rootRef, .symbol = publicEntry.symbol, .namespacePath = publicEntry.namespacePath});
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

    ModuleApiNamespaceNode* findOrAppendNamespaceChild(ModuleApiNamespaceNode& node, const IdentifierRef idRef)
    {
        const auto it = std::ranges::find_if(node.children, [&](const ModuleApiNamespaceNode& child) { return child.idRef == idRef; });
        if (it != node.children.end())
            return &*it;

        node.children.push_back({.idRef = idRef});
        return &node.children.back();
    }

    ModuleApiNamespaceNode::ImplNode* findOrAppendNamespaceImpl(ModuleApiNamespaceNode& node, const SourceFile& file, const AstNodeRef implRef, Utf8&& prefix)
    {
        const auto it = std::ranges::find_if(node.impls, [&](const ModuleApiNamespaceNode::ImplNode& child) { return child.file == &file && child.implRef == implRef; });
        if (it != node.impls.end())
            return &*it;

        node.impls.push_back({.file = &file, .implRef = implRef, .prefix = std::move(prefix)});
        return &node.impls.back();
    }

    void appendNamespaceSnippet(ModuleApiNamespaceNode& rootNode, std::span<const IdentifierRef> namespacePath, Utf8&& snippet)
    {
        ModuleApiNamespaceNode* currentNode = &rootNode;
        for (const IdentifierRef idRef : namespacePath)
        {
            currentNode = findOrAppendNamespaceChild(*currentNode, idRef);
            SWC_ASSERT(currentNode);
        }

        currentNode->snippets.push_back(std::move(snippet));
    }

    void appendNamespaceImplSnippet(ModuleApiNamespaceNode& rootNode, std::span<const IdentifierRef> namespacePath, const SourceFile& file, const AstNodeRef implRef, Utf8&& prefix, Utf8&& snippet)
    {
        ModuleApiNamespaceNode* currentNode = &rootNode;
        for (const IdentifierRef idRef : namespacePath)
        {
            currentNode = findOrAppendNamespaceChild(*currentNode, idRef);
            SWC_ASSERT(currentNode);
        }

        auto* implNode = findOrAppendNamespaceImpl(*currentNode, file, implRef, std::move(prefix));
        SWC_ASSERT(implNode);
        implNode->snippets.push_back(std::move(snippet));
    }

    void appendNamespaceImplNode(Utf8& outContent, const ModuleApiNamespaceNode::ImplNode& node, const Utf8& indent, const std::string_view eol)
    {
        if (node.prefix.empty())
            return;

        appendIndentedSnippet(outContent, node.prefix.view(), indent.view(), eol);
        outContent += eol;
        outContent += indent;
        outContent += "{";
        outContent += eol;

        Utf8 childIndent = indent;
        childIndent += "    ";
        for (const Utf8& snippet : node.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), childIndent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        outContent += indent;
        outContent += "}";
        outContent += eol;
    }

    void appendNamespaceNode(TaskContext& ctx, Utf8& outContent, const ModuleApiNamespaceNode& node, const Utf8& indent, std::string_view eol)
    {
        if (node.idRef.isInvalid() && node.snippets.empty() && node.impls.empty() && node.children.empty())
            return;

        Utf8 childIndent = indent;
        if (node.idRef.isValid())
        {
            outContent += indent;
            outContent += "namespace ";
            outContent += ctx.idMgr().get(node.idRef).name;
            outContent += eol;
            outContent += indent;
            outContent += "{";
            outContent += eol;

            childIndent += "    ";
        }

        for (const Utf8& snippet : node.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), childIndent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        for (const auto& implNode : node.impls)
            appendNamespaceImplNode(outContent, implNode, childIndent, eol);

        for (const ModuleApiNamespaceNode& child : node.children)
            appendNamespaceNode(ctx, outContent, child, childIndent, eol);

        if (node.idRef.isValid())
        {
            outContent += indent;
            outContent += "}";
            outContent += eol;
        }
    }

    void appendNamespaceTree(TaskContext& ctx, Utf8& outContent, const ModuleApiNamespaceNode& rootNode, std::string_view eol)
    {
        for (const Utf8& snippet : rootNode.snippets)
        {
            outContent += snippet;
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        for (const auto& implNode : rootNode.impls)
            appendNamespaceImplNode(outContent, implNode, {}, eol);

        for (const ModuleApiNamespaceNode& child : rootNode.children)
            appendNamespaceNode(ctx, outContent, child, {}, eol);
    }

    Result formatGeneratedModuleApiContent(TaskContext& ctx, Utf8& outContent)
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

    Result buildGeneratedModuleApiContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;

        ModuleApiNamespaceNode namespaceTree;

        for (const ModuleApiGeneratedRoot& root : roots)
        {
            Utf8 sanitizedSnippet;
            SWC_RESULT(buildGeneratedRootSnippet(ctx, root, eol, sanitizedSnippet));
            if (sanitizedSnippet.empty())
                continue;

            const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
            const SymbolImpl* symImpl = symbolFunction ? symbolFunction->declImplContext() : nullptr;
            if (symbolFunction && symImpl && symImpl->isForStruct() && symImpl->decl())
            {
                Utf8 implPrefix;
                if (tryBuildImplPrefix(ctx, root, eol, implPrefix))
                {
                    const AstNodeRef implRef = symImpl->decl()->nodeRef(root.file->ast());
                    appendNamespaceImplSnippet(namespaceTree, root.namespacePath, *root.file, implRef, std::move(implPrefix), std::move(sanitizedSnippet));
                    continue;
                }
            }

            appendNamespaceSnippet(namespaceTree, root.namespacePath, std::move(sanitizedSnippet));
        }

        appendNamespaceTree(ctx, outContent, namespaceTree, eol);

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
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
        if (!symbol.isPublic())
            return;

        const SourceFile* sourceFile = sourceFileFromRef(ctx.compiler(), symbol.srcViewRef());
        if (!sourceFile || !sourceFile->hasFlag(FileFlagsE::ModuleSrc) || sourceFile->isImportedApi())
            return;

        if (!isSupportedPublicDeclSymbol(symbol))
            return;

        const AstNodeRef declRef = symbol.decl()->nodeRef(sourceFile->ast());
        if (declRef.isInvalid())
            return;
        if (!isExportedPublicDeclScope(*sourceFile, declRef, symbol))
            return;

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = findExportDeclRoot(*sourceFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return;

        if (!extractPublicNamespacePath(symbol, publicEntry.namespacePath))
            return;

        const AstNodeRef rootRef = publicEntry.rootRef;
        if (rootRef.isInvalid())
            return;

        recordPublicEntry(state, symbol.srcViewRef(), publicEntry);
    }

    Result exportFiles(TaskContext& ctx)
    {
        CompilerInstance& compiler     = ctx.compiler();
        const fs::path&   exportApiDir = compiler.cmdLine().exportApiDir;
        if (exportApiDir.empty())
            return Result::Continue;

        std::unordered_map<SourceViewRef, ModuleApiFileEntry> collectedEntries;
        for (size_t i = 0; i < compiler.numPerThreadData(); ++i)
            mergeThreadData(collectedEntries, compiler.moduleApiPerThreadData(i));

        const Utf8                          moduleNamespace      = buildModuleNamespaceName(compiler);
        const SourceFile*                   firstSourceFile      = nullptr;
        bool                                hasModuleSources     = false;
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

        const fs::path generatedDstPath  = buildGeneratedModuleApiPath(compiler, exportApiDir);
        const Utf8     generatedFileName = generatedDstPath.filename().string();
        if (exportedFileNames.contains(generatedFileName))
            return Result::Continue;

        Utf8 content;
        SWC_RESULT(buildGeneratedModuleApiContent(ctx, generatedRoots, moduleNamespace.view(), preferredLineEnding(*firstSourceFile), content));
        if (writeModuleApiFile(ctx, generatedDstPath, content.view()) != Result::Continue)
            return Result::Error;

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
