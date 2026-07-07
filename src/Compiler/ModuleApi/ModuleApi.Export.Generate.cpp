#include "pch.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();
using namespace ModuleApi::Export;

namespace
{
    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, std::string_view eol);

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

    void appendMissingFunctionAttributeLine(Utf8& ioPrefix, const SymbolFunction& symbolFunction, const std::string_view eol, const std::string_view snippet, const RtAttributeFlagsE flag, const std::string_view marker, const std::string_view attrText)
    {
        if (!symbolFunction.attributes().hasRtFlag(flag))
            return;
        if (snippet.contains(marker))
            return;

        ioPrefix += attrText;
        ioPrefix += eol;
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
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView() || ast.isAdditionalNode(bodyRef))
            return false;

        const AstNode& bodyNode = ast.node(bodyRef);
        if (!bodyNode.tokRef().isValid())
            return false;

        const SourceView&      srcView         = moduleApiNodeSourceView(ctx, ast, root.nodeRef);
        const uint32_t         bodyStartOffset = sourceTokenByteStart(srcView, srcView.token(bodyNode.tokRef()));
        const std::string_view source          = srcView.stringView();
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
        result += "    internal swagOpaqueStorage: [";
        result += std::format("{}", symbolStruct->sizeOf());
        result += "] u8";
        result += eol;
        result += "}";
        return result;
    }

    bool isGeneratedModuleApiSourceFunction(TaskContext& ctx, const SymbolFunction& symbolFunction)
    {
        if (!symbolFunction.isPublic())
            return false;
        if (!symbolFunction.decl() || symbolFunction.decl()->isNot(AstNodeId::FunctionDecl))
            return false;
        if (symbolFunction.attributes().hasRtFlag(RtAttributeFlagsE::PlaceHolder))
            return false;
        if (symbolFunction.supportsPublicApiForeignExport() && supportsGeneratedModuleApiForeignFunctions(ctx.compiler()))
            return false;

        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbolFunction);
        if (!sourceFile || !ModuleApi::isCurrentModuleSourceFile(*sourceFile))
            return false;

        AstNodeRef declRef;
        if (!ModuleApi::Internal::tryFindNodeRef(sourceFile->ast(), symbolFunction.decl(), declRef))
            return false;
        return ModuleApi::Internal::isExportedPublicDeclScope(*sourceFile, declRef, symbolFunction);
    }

    bool hasGeneratedModuleApiSourceMethod(TaskContext& ctx, const SymbolStruct& symbolStruct)
    {
        for (const SymbolFunction* method : symbolStruct.declaredMethods())
        {
            if (method && isGeneratedModuleApiSourceFunction(ctx, *method))
                return true;
        }

        return false;
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
        Utf8 prefix;
        appendMissingFunctionAttributeLine(prefix, symbolFunction, eol, ioSnippet, RtAttributeFlagsE::Macro, "Macro", "#[Swag.Macro]");
        appendMissingFunctionAttributeLine(prefix, symbolFunction, eol, ioSnippet, RtAttributeFlagsE::Mixin, "Mixin", "#[Swag.Mixin]");
        appendMissingFunctionAttributeLine(prefix, symbolFunction, eol, ioSnippet, RtAttributeFlagsE::Inline, "Inline", "#[Swag.Inline]");
        appendMissingFunctionAttributeLine(prefix, symbolFunction, eol, ioSnippet, RtAttributeFlagsE::ConstExpr, "ConstExpr", "#[Swag.ConstExpr]");
        appendMissingFunctionAttributeLine(prefix, symbolFunction, eol, ioSnippet, RtAttributeFlagsE::Implicit, "Implicit", "#[Swag.Implicit]");

        // The borrow summaries are computed facts, not source attributes: re-emit them
        // so importers can judge their call sites against this function's parameters.
        // The export runs after the final sema drain, so the masks include the
        // transitive bits added by the summary fixpoint.
        const uint64_t returnsMask = symbolFunction.returnBorrowsParamsMask();
        const uint64_t storesMask  = symbolFunction.storesParamsMask();
        const uint64_t intoPairs   = symbolFunction.storesIntoParamPairs();
        const uint64_t freesMask   = symbolFunction.freesParamsMask();
        if ((returnsMask != 0 || storesMask != 0 || intoPairs != 0 || freesMask != 0) && !ioSnippet.contains("BorrowSummary"))
        {
            prefix += std::format("#[Swag.BorrowSummary({}, {}, {}, {})]", returnsMask, storesMask, intoPairs, freesMask);
            prefix += eol;
        }

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

    bool isModuleApiTypeNameQualifierBoundary(const char c)
    {
        return !std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '.';
    }

    Utf8 stripCurrentModuleTypeQualifiers(Utf8 typeName, const std::string_view moduleNamespace)
    {
        if (moduleNamespace.empty())
            return typeName;

        Utf8 prefix;
        prefix += moduleNamespace;
        prefix += ".";

        size_t pos = typeName.find(prefix.view());
        while (pos != std::string_view::npos)
        {
            if (pos == 0 || isModuleApiTypeNameQualifierBoundary(typeName[pos - 1]))
            {
                typeName.erase(pos, prefix.size());
                pos = typeName.find(prefix.view(), pos);
                continue;
            }

            pos = typeName.find(prefix.view(), pos + prefix.size());
        }

        return typeName;
    }

    Utf8 buildGeneratedModuleApiTypeName(TaskContext& ctx, const TypeRef typeRef)
    {
        const Utf8 moduleNamespace = buildModuleNamespaceName(ctx.compiler());
        Utf8       typeName        = ctx.typeMgr().get(typeRef).toFullName(ctx);
        return stripCurrentModuleTypeQualifiers(std::move(typeName), moduleNamespace.view());
    }

    bool tryBuildFunctionDeclPrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction || !root.file || !symbolFunction->decl())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return false;

        if (symbolFunction->decl()->isNot(AstNodeId::FunctionDecl))
            return false;

        uint32_t bodyStartOffset = 0;
        if (tryFindFunctionBodyStartOffset(root, bodyStartOffset))
            endOffset = bodyStartOffset;

        const SourceView&      srcView = moduleApiNodeSourceView(ctx, root.file->ast(), root.nodeRef);
        const std::string_view source  = srcView.stringView();
        endOffset                      = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
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
                const Utf8 returnTypeName = buildGeneratedModuleApiTypeName(ctx, symbolFunction->returnTypeRef());
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
            case CallConvKind::Swag:
                callConvName = "Swag.CallConv.Swag";
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

    // Emit a bare `impl Interface for Struct {}` for an empty interface impl that has no
    // member functions to reconstruct it from. The impl prefix (up to the opening brace) is
    // taken verbatim from the source; an empty body is appended.
    bool tryBuildEmptyInterfaceImplSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outSnippet)
    {
        if (!root.file || !root.symbol)
            return false;

        const auto* symImpl = root.symbol->safeCast<SymbolImpl>();
        if (!symImpl || !symImpl->isForInterface())
            return false;

        AstNodeRef implRef;
        if (!ModuleApi::Internal::tryFindNodeRef(root.file->ast(), symImpl->decl(), implRef))
            return false;

        Utf8 implPrefix;
        if (!tryBuildImplPrefix(ctx, *root.file, implRef, eol, implPrefix))
            return false;

        outSnippet = std::move(implPrefix);
        outSnippet += eol;
        outSnippet += "{";
        outSnippet += eol;
        outSnippet += "}";
        return true;
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

    const SymbolImpl* semanticImplContext(const Symbol* symbol)
    {
        if (!symbol)
            return nullptr;

        if (const auto* symbolFunction = symbol->safeCast<SymbolFunction>())
            return symbolFunction->declImplContext();

        const SymbolMap* ownerSymMap = symbol->ownerSymMap();
        if (ownerSymMap && ownerSymMap->isImpl())
            return &ownerSymMap->cast<SymbolImpl>();

        return nullptr;
    }

    uint32_t moduleApiRootSortByte(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef)
    {
        constexpr uint32_t moduleApiInvalidByte = 0xFFFFFFFFu;
        uint32_t           startOffset          = moduleApiInvalidByte;
        if (!tryGetModuleApiSnippetStartOffset(ctx, file, nodeRef, startOffset))
            return moduleApiInvalidByte;

        return startOffset;
    }

    struct ModuleApiRootSortProjection
    {
        TaskContext*      ctx  = nullptr;
        const SourceFile* file = nullptr;

        uint32_t operator()(const ModuleApiPublicEntry& entry) const
        {
            SWC_ASSERT(ctx != nullptr);
            SWC_ASSERT(file != nullptr);
            return moduleApiRootSortByte(*ctx, *file, entry.rootRef);
        }
    };

    bool sameGeneratedRoot(const ModuleApiGeneratedRoot& root, const SourceFile& file, const AstNodeRef nodeRef, std::span<const IdentifierRef> namespacePath)
    {
        return root.file == &file &&
               root.nodeRef == nodeRef &&
               sameNamespacePath(root.namespacePath, namespacePath);
    }

    void appendGeneratedGenericRootMethodRoots(TaskContext& ctx, const SymbolStruct& symbolStruct, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (!symbolStruct.isGenericRoot() || symbolStruct.isGenericInstance())
            return;

        for (const SymbolFunction* method : symbolStruct.declaredMethods())
        {
            if (!method || !isGeneratedModuleApiSourceFunction(ctx, *method))
                continue;

            const SourceFile* sourceFile = ctx.compiler().sourceViewFile(*method);
            const SourceFile* astFile    = ctx.compiler().ownerSourceFile(method->srcViewRef());
            if (!astFile)
                astFile = sourceFile;
            if (!sourceFile || !astFile)
                continue;

            AstNodeRef declRef;
            if (!ModuleApi::Internal::tryFindNodeRef(astFile->ast(), method->decl(), declRef))
                continue;

            ModuleApiGeneratedRoot methodRoot;
            methodRoot.file    = astFile;
            methodRoot.nodeRef = ModuleApi::Internal::findExportDeclRoot(*astFile, declRef);
            methodRoot.symbol  = method;
            if (methodRoot.nodeRef.isInvalid())
                continue;
            if (!ModuleApi::Internal::extractPublicNamespacePath(ctx, *astFile, declRef, *method, methodRoot.namespacePath))
                continue;

            appendGeneratedRootUnique(outRoots, std::move(methodRoot));
        }
    }

    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        outSnippet.clear();
        std::string_view snippetText;
        if (!root.file || !tryGetModuleApiSnippet(ctx, *root.file, root.nodeRef, snippetText))
            return Result::Continue;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return Result::Continue;

        outSnippet = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, snippetText, eol);
        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
            prependMissingFunctionAttributes(*symbolFunction, eol, outSnippet);
        return Result::Continue;
    }
}

namespace ModuleApi::Export
{
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
        if (!tryGetModuleApiSnippetOffsets(ctx, file, implRef, startOffset, endOffset))
            return false;

        const AstNode&    implNode    = ast.node(implRef);
        const TokenRef    startTokRef = moduleApiSnippetStartTokRef(ast, implNode);
        const TokenRef    endTokRef   = implNode.tokRefEnd(ast);
        const SourceView& srcView     = moduleApiNodeSourceView(ctx, ast, implRef);

        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (token.id != TokenId::SymLeftCurly)
                continue;

            endOffset = sourceTokenByteStart(srcView, token);
            break;
        }

        const std::string_view source = srcView.stringView();
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return false;

        outPrefix = buildSanitizedModuleApiSnippet(ctx, file, implRef, startOffset, source.substr(startOffset, endOffset - startOffset), eol);
        trimTrailingModuleApiWhitespace(outPrefix);
        return !outPrefix.empty();
    }

    Result buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outSnippet, ModuleApiValidationStack& validationStack)
    {
        outSnippet.clear();
        if (!root.file)
            return Result::Continue;

        if (root.symbol && root.symbol->isImpl())
        {
            tryBuildEmptyInterfaceImplSnippet(ctx, root, eol, outSnippet);
            return Result::Continue;
        }

        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
        {
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
            SWC_RESULT(validatePublicTypeSymbol(ctx, *root.symbol, validationStack));
        }

        if (root.symbol && root.symbol->isStruct() && isModuleApiOpaqueType(*root.symbol))
        {
            if (const auto* symbolStruct = root.symbol->safeCast<SymbolStruct>(); symbolStruct && symbolStruct->isGenericRoot() && !symbolStruct->isGenericInstance())
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

            if (const auto* symbolStruct = root.symbol->safeCast<SymbolStruct>(); symbolStruct && hasGeneratedModuleApiSourceMethod(ctx, *symbolStruct))
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

            outSnippet = buildOpaqueTypeSnippet(ctx, root, eol);
            return Result::Continue;
        }

        return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
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

    bool tryFindSemanticImplRef(TaskContext& ctx, const ModuleApiGeneratedRoot& root, AstNodeRef& outImplRef, const SourceFile*& outImplFile)
    {
        outImplRef  = AstNodeRef::invalid();
        outImplFile = nullptr;

        const SymbolImpl* symImpl = semanticImplContext(root.symbol);
        if (!symImpl || !symImpl->decl())
            return false;

        const SourceFile* implFile = ctx.compiler().ownerSourceFile(symImpl->srcViewRef());
        if (!implFile)
            implFile = ctx.compiler().sourceViewFile(*symImpl);
        if (!implFile)
            return false;

        AstNodeRef implRef;
        if (!ModuleApi::Internal::tryFindNodeRef(implFile->ast(), symImpl->decl(), implRef))
            return false;

        outImplRef  = implRef;
        outImplFile = implFile;
        return true;
    }

    void appendGeneratedRootUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, ModuleApiGeneratedRoot&& root)
    {
        if (!root.file || root.nodeRef.isInvalid())
            return;

        for (const ModuleApiGeneratedRoot& existing : outRoots)
        {
            if (sameGeneratedRoot(existing, *root.file, root.nodeRef, root.namespacePath))
                return;
        }

        outRoots.push_back(std::move(root));
    }

    void appendGeneratedRootsForFile(TaskContext& ctx, const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (fileEntry.publicEntries.empty())
            return;

        const SourceFile* astFile = ctx.compiler().ownerSourceFile(file.ast().srcView().ref());
        if (!astFile)
            astFile = &file;

        std::vector<ModuleApiPublicEntry> sortedEntries = fileEntry.publicEntries;
        std::ranges::stable_sort(sortedEntries, {}, ModuleApiRootSortProjection{.ctx = &ctx, .file = astFile});

        for (const ModuleApiPublicEntry& publicEntry : sortedEntries)
        {
            appendGeneratedRootUnique(outRoots, {.file = astFile, .nodeRef = publicEntry.rootRef, .symbol = publicEntry.symbol, .namespacePath = publicEntry.namespacePath});
            if (const auto* symbolStruct = publicEntry.symbol ? publicEntry.symbol->safeCast<SymbolStruct>() : nullptr)
                appendGeneratedGenericRootMethodRoots(ctx, *symbolStruct, outRoots);
        }
    }
}

SWC_END_NAMESPACE();
