#include "pch.h"
#include "Compiler/ModuleApi/ModuleApiExport.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using ModuleApiExport::appendGeneratedRootUnique;
    using ModuleApiExport::buildModuleNamespaceName;
    using ModuleApiExport::buildSanitizedModuleApiSnippet;
    using ModuleApiExport::extractPublicNamespacePath;
    using ModuleApiExport::findExportDeclRoot;
    using ModuleApiExport::isCurrentModuleSourceFile;
    using ModuleApiExport::isCurrentModuleSymbol;
    using ModuleApiExport::isExportedPublicDeclScope;
    using ModuleApiExport::isModuleApiOpaqueType;
    using ModuleApiExport::isWholeFileExportedSymbol;
    using ModuleApiExport::ModuleApiGeneratedRoot;
    using ModuleApiExport::moduleApiNodeSourceView;
    using ModuleApiExport::moduleApiSnippetStartTokRef;
    using ModuleApiExport::removeModuleApiAttributes;
    using ModuleApiExport::sameNamespacePath;
    using ModuleApiExport::sourceTokenByteEnd;
    using ModuleApiExport::sourceTokenByteStart;
    using ModuleApiExport::tryBuildImplPrefix;
    using ModuleApiExport::tryFindReachableNodeRef;
    using ModuleApiExport::tryGetModuleApiSnippet;
    using ModuleApiExport::tryGetModuleApiSnippetOffsets;
    using ModuleApiExport::tryGetModuleApiSnippetStartOffset;

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

    bool isGeneratedInlineBodySymbolAvailable(TaskContext& ctx, const SymbolFunction& function, const Symbol& symbol)
    {
        if (!isCurrentModuleSymbol(ctx.compiler(), symbol) || isWholeFileExportedSymbol(ctx.compiler(), symbol))
            return true;

        if (const auto* variable = symbol.safeCast<SymbolVariable>())
        {
            if (variable->isFunctionLocalVariable(function) || function.containsLocalVariable(*variable))
                return true;
        }

        // A field, a member constant and an enum value travel with the type that declares them,
        // and the body is re-emitted in that same generated file, so it reads them exactly as it
        // did in the module it came from: the access rules answer with the file the code was
        // written in, not with the one that ends up calling it. An opaque type publishes storage
        // instead of members, so nothing a body names inside one can bind again.
        if (symbol.isValueExpr())
        {
            bool ownedByExportedType = false;
            for (const SymbolMap* owner = symbol.ownerSymMap(); owner; owner = owner->ownerSymMap())
            {
                if (!owner->isStruct() && !owner->isEnum())
                    continue;
                if (!owner->isPublic() || isModuleApiOpaqueType(*owner))
                    return false;

                ownedByExportedType = true;
            }

            if (ownedByExportedType)
                return true;
        }

        return symbol.isPublic();
    }

    bool isGeneratedInlineBodyIntrinsicExportable(TaskContext& ctx, const Ast& ast, const AstNodeRef nodeRef, const AstNode& node)
    {
        if (node.isNot(AstNodeId::IntrinsicCallExpr))
            return true;

        // A generated API carries the body, not the intrinsic's effect contract. One that
        // computes from its operands alone means the same thing wherever it is re-emitted; an
        // atomic, a context query, or a report about the running program answers about the
        // module it runs in, and stays behind the foreign call that owns that boundary.
        const SourceView& srcView = moduleApiNodeSourceView(ctx, ast, nodeRef);
        return Token::isPortableIntrinsic(srcView.token(node.tokRef()).id);
    }

    bool canExportGeneratedInlineBody(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const SymbolFunction& function)
    {
        const auto* functionDecl = function.decl() ? function.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!root.file || !functionDecl || functionDecl->nodeBodyRef.isInvalid())
            return false;

        bool       canExport = true;
        const Ast& ast       = root.file->ast();
        Ast::visit(ast, functionDecl->nodeBodyRef, [&](const AstNodeRef nodeRef, const AstNode& node) {
            if (!isGeneratedInlineBodyIntrinsicExportable(ctx, ast, nodeRef, node))
            {
                canExport = false;
                return Ast::VisitResult::Stop;
            }

            const NodePayload::StoredView view = root.file->nodePayloadContext().viewStored(ctx, nodeRef);
            if (view.hasSymbol && view.sym && !isGeneratedInlineBodySymbolAvailable(ctx, function, *view.sym))
            {
                canExport = false;
                return Ast::VisitResult::Stop;
            }

            if (view.hasSymbolList)
            {
                for (const Symbol* symbol : view.symList)
                {
                    if (symbol && !isGeneratedInlineBodySymbolAvailable(ctx, function, *symbol))
                    {
                        canExport = false;
                        return Ast::VisitResult::Stop;
                    }
                }
            }

            return Ast::VisitResult::Continue;
        });
        return canExport;
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

    // Whether the snippet already spells `marker` as an attribute.
    //
    // The snippet is source text, so a plain substring search also matches an identifier that
    // happens to contain the attribute name, and a function named 'depDiscardableCount' would
    // then lose its '#[Swag.Discardable]'. Only a spelling bounded like a member of an
    // attribute list counts: '#[Inline]', '#[Swag.Inline]', or either inside a list.
    bool snippetSpellsAttribute(const std::string_view snippet, const std::string_view marker)
    {
        for (size_t pos = snippet.find(marker); pos != std::string_view::npos; pos = snippet.find(marker, pos + 1))
        {
            const size_t after  = pos + marker.size();
            const char   before = pos == 0 ? '\0' : snippet[pos - 1];
            const char   next   = after >= snippet.size() ? '\0' : snippet[after];
            if ((before == '[' || before == '.' || before == ' ' || before == ',') && (next == ']' || next == ','))
                return true;
        }

        return false;
    }

    // The generated API opens with the runtime prelude in scope, which is what lets a copied
    // '#[Inline]' resolve, so every attribute the generator writes is spelled unqualified too.
    void appendMissingFunctionAttribute(SmallVector<Utf8>& ioAttributes, const SymbolFunction& symbolFunction, const std::string_view snippet, const RtAttributeFlagsE flag, const std::string_view marker)
    {
        if (!symbolFunction.attributes().hasRtFlag(flag))
            return;
        if (snippetSpellsAttribute(snippet, marker))
            return;

        ioAttributes.push_back(Utf8{marker});
    }

    // One list holds every attribute of a declaration, so an entry costs one line whatever it
    // states.
    Utf8 buildAttributeListLine(std::span<const Utf8> attributes, const std::string_view eol)
    {
        if (attributes.empty())
            return {};

        Utf8 result = "#[";
        for (size_t index = 0; index < attributes.size(); ++index)
        {
            if (index != 0)
                result += ", ";
            result += attributes[index];
        }

        result += "]";
        result += eol;
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
            prefix += "#[Opaque]";
            prefix += eol;
            prefix += symbolStruct->isUnion() ? "union " : "struct ";
            prefix += symbolStruct->name(ctx);
        }

        static constexpr std::string_view MATERIALIZED_LAYOUT_ATTRIBUTES[] = {"Pack"};
        removeModuleApiAttributes(ctx, prefix, MATERIALIZED_LAYOUT_ATTRIBUTES);

        Utf8     result;
        uint32_t alignValue = 0;
        if (symbolStruct->alignment() > 1 && !tryGetSwagAttributeIntValue(alignValue, ctx, *symbolStruct, "Align"))
        {
            result += std::format("#[Align({})]", symbolStruct->alignment());
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
        if (!sourceFile || !isCurrentModuleSourceFile(*sourceFile))
            return false;

        AstNodeRef declRef;
        if (!tryFindReachableNodeRef(sourceFile->ast(), symbolFunction.decl(), declRef))
            return false;
        return isExportedPublicDeclScope(*sourceFile, declRef, symbolFunction);
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

    void collectMissingFunctionAttributes(SmallVector<Utf8>& ioAttributes, const SymbolFunction& symbolFunction, const bool hasExportedBody, const Utf8& snippet)
    {
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Macro, "Macro");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Mixin, "Mixin");

        // 'Inline' asks the consumer to expand the body, so it only means something where the
        // body travels with the declaration. Publishing it on an entry the API reduced to a
        // foreign call promises an expansion that cannot happen.
        if (hasExportedBody)
            appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Inline, "Inline");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::ConstExpr, "ConstExpr");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Implicit, "Implicit");

        // 'Discardable' is a fact about the call site, not about the body: without it an
        // importer has to write 'discard' where a caller inside the module does not.
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Discardable, "Discardable");

        // The borrow summaries are computed facts, not source attributes: re-emit them
        // so importers can judge their call sites against this function's parameters.
        // The export runs after the final sema drain, so the masks include the
        // transitive bits added by the summary fixpoint.
        const uint64_t returnsMask        = symbolFunction.returnBorrowsParamsMask();
        const uint64_t storesMask         = symbolFunction.storesParamsMask();
        const uint64_t intoPairs          = symbolFunction.storesIntoParamPairs();
        const uint64_t freesMask          = symbolFunction.freesParamsMask();
        const uint64_t reallocatesMask    = symbolFunction.reallocatesParamsMask();
        const uint64_t returnsPayloadMask = symbolFunction.returnsPayloadParamsMask();
        if ((returnsMask != 0 || storesMask != 0 || intoPairs != 0 || freesMask != 0 || reallocatesMask != 0 || returnsPayloadMask != 0) && !snippet.contains("BorrowSummary"))
            ioAttributes.push_back(Utf8{std::format("BorrowSummary({}, {}, {}, {}, {}, {})", returnsMask, storesMask, intoPairs, freesMask, reallocatesMask, returnsPayloadMask)});
    }

    void prependMissingFunctionAttributes(const SymbolFunction& symbolFunction, const std::string_view eol, const bool hasExportedBody, Utf8& ioSnippet)
    {
        SmallVector<Utf8> attributes;
        collectMissingFunctionAttributes(attributes, symbolFunction, hasExportedBody, ioSnippet);

        const Utf8 line = buildAttributeListLine(attributes.span(), eol);
        if (!line.empty())
            ioSnippet = line + ioSnippet;
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

                case TokenId::KwdFail:
                case TokenId::KwdWhere:
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

    // An entry of a generated module API states only what an importer cannot recompute.
    // The module is the one the API file describes, the calling convention is Swag, and
    // the flattened symbol name is the scoped declaration name; each of those is the
    // default an importer applies on its own. Only an overload carries a name, because
    // its disambiguating suffix depends on the whole overload set.
    Utf8 buildModuleApiForeignAttribute(TaskContext& ctx, const SymbolFunction& symbolFunction)
    {
        SWC_ASSERT(symbolFunction.callConvKind() == CallConvKind::Swag);

        const Utf8 apiName = symbolFunction.computePublicApiSymbolName(ctx);
        if (apiName == symbolFunction.computePublicApiBaseSymbolName(ctx))
            return "Foreign";

        return Utf8{std::format("Foreign(function: \"{}\")", apiName.c_str())};
    }

    Utf8 buildFunctionSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction)
            return {};

        Utf8 prefix;
        if (!tryBuildFunctionDeclPrefix(ctx, root, eol, prefix))
            return {};

        static constexpr std::string_view BODY_ATTRIBUTES[] = {"Inline", "NoInline", "Safety", "Sanity", "Optimize", "Warning"};
        removeModuleApiAttributes(ctx, prefix, BODY_ATTRIBUTES);
        trimTrailingModuleApiDeclarationSeparator(prefix);
        if (prefix.empty())
            return {};

        SmallVector<Utf8> attributes;
        if (!symbolFunction->isForeign())
            attributes.push_back(buildModuleApiForeignAttribute(ctx, *symbolFunction));
        collectMissingFunctionAttributes(attributes, *symbolFunction, false, prefix);

        Utf8 result = buildAttributeListLine(attributes.span(), eol);
        result += prefix;
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
        if (!tryFindReachableNodeRef(root.file->ast(), symImpl->decl(), implRef))
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
            if (!tryFindReachableNodeRef(astFile->ast(), method->decl(), declRef))
                continue;

            ModuleApiGeneratedRoot methodRoot;
            methodRoot.file    = astFile;
            methodRoot.nodeRef = findExportDeclRoot(*astFile, declRef);
            methodRoot.symbol  = method;
            if (methodRoot.nodeRef.isInvalid())
                continue;
            if (!extractPublicNamespacePath(ctx, *astFile, declRef, *method, methodRoot.namespacePath))
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
            prependMissingFunctionAttributes(*symbolFunction, eol, true, outSnippet);
        return Result::Continue;
    }
}

namespace ModuleApiExport
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
                if (symbolFunction->attributes().hasRtFlag(RtAttributeFlagsE::Inline) && canExportGeneratedInlineBody(ctx, root, *symbolFunction))
                    return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

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
        if (!tryFindReachableNodeRef(implFile->ast(), symImpl->decl(), implRef))
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
