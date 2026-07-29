#include "pch.h"
#include "Compiler/Doc/DocGenerator.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class DocItemKind : uint8_t
    {
        Namespace,
        Struct,
        Interface,
        Enum,
        Constant,
        Alias,
        Attribute,
        Function,
    };

    struct PageOptions
    {
        Runtime::BuildCfgDocKind kind = Runtime::BuildCfgDocKind::None;
        Utf8                     outputName;
        Utf8                     titleToc;
        Utf8                     titleContent;
        Utf8                     css;
        Utf8                     icon;
        Utf8                     morePages;
        Utf8                     quoteIconNote;
        Utf8                     quoteIconTip;
        Utf8                     quoteIconWarning;
        Utf8                     quoteIconAttention;
        Utf8                     quoteIconExample;
        Utf8                     quoteTitleNote;
        Utf8                     quoteTitleTip;
        Utf8                     quoteTitleWarning;
        Utf8                     quoteTitleAttention;
        Utf8                     quoteTitleExample;
        uint32_t                 syntaxDefaultColor = 0x00222222;
        bool                     hasSwagWatermark   = true;
    };

    struct DocOverload
    {
        const Symbol*     symbol = nullptr;
        const SourceFile* file   = nullptr;
        Utf8              signature;
        std::vector<Utf8> commentLines;
        uint32_t          sourceLine = 0;
    };

    struct DocItem
    {
        DocItemKind              kind = DocItemKind::Function;
        Utf8                     fullName;
        Utf8                     displayName;
        Utf8                     category;
        std::vector<DocOverload> overloads;
    };

    struct RenderContext
    {
        TaskContext*                          ctx     = nullptr;
        const PageOptions*                    options = nullptr;
        const std::unordered_map<Utf8, Utf8>* references;
    };

    struct ApiDocument
    {
        std::vector<DocItem>           items;
        std::unordered_map<Utf8, Utf8> references;
        Utf8                           toc;
        Utf8                           content;
    };

    std::mutex               g_RuntimeDocMutex;
    std::unordered_set<Utf8> g_GeneratedRuntimeDocs;
    std::mutex               g_StylesheetMutex;

    Utf8 fromRuntimeString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};
        return Utf8(value.ptr, static_cast<size_t>(value.length));
    }

    PageOptions getPageOptions(const CompilerInstance& compiler)
    {
        const Runtime::BuildCfgGenDoc& genDoc = compiler.buildCfg().genDoc;

        PageOptions result;
        result.kind                = genDoc.kind;
        result.outputName          = fromRuntimeString(genDoc.outputName);
        result.titleToc            = fromRuntimeString(genDoc.titleToc);
        result.titleContent        = fromRuntimeString(genDoc.titleContent);
        result.css                 = fromRuntimeString(genDoc.css);
        result.icon                = fromRuntimeString(genDoc.icon);
        result.morePages           = fromRuntimeString(genDoc.morePages);
        result.quoteIconNote       = fromRuntimeString(genDoc.quoteIconNote);
        result.quoteIconTip        = fromRuntimeString(genDoc.quoteIconTip);
        result.quoteIconWarning    = fromRuntimeString(genDoc.quoteIconWarning);
        result.quoteIconAttention  = fromRuntimeString(genDoc.quoteIconAttention);
        result.quoteIconExample    = fromRuntimeString(genDoc.quoteIconExample);
        result.quoteTitleNote      = fromRuntimeString(genDoc.quoteTitleNote);
        result.quoteTitleTip       = fromRuntimeString(genDoc.quoteTitleTip);
        result.quoteTitleWarning   = fromRuntimeString(genDoc.quoteTitleWarning);
        result.quoteTitleAttention = fromRuntimeString(genDoc.quoteTitleAttention);
        result.quoteTitleExample   = fromRuntimeString(genDoc.quoteTitleExample);
        result.syntaxDefaultColor  = genDoc.syntaxDefaultColor;
        result.hasSwagWatermark    = genDoc.hasSwagWatermark;

        if (!compiler.cmdLine().docCss.empty())
            result.css = compiler.cmdLine().docCss;
        return result;
    }

    PageOptions getRuntimePageOptions(const CompilerInstance& compiler)
    {
        PageOptions result     = getPageOptions(compiler);
        result.kind            = Runtime::BuildCfgDocKind::Api;
        result.outputName      = "swag.runtime";
        result.titleContent    = "Swag Runtime";
        if (result.css.empty())
            result.css = "style.css";
        return result;
    }

    std::string_view trimView(std::string_view value)
    {
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front())))
            value.remove_prefix(1);
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
            value.remove_suffix(1);
        return value;
    }

    Utf8 trimCopy(std::string_view value)
    {
        return Utf8(trimView(value));
    }

    std::vector<Utf8> splitLines(const std::string_view text)
    {
        std::vector<Utf8> result;
        size_t            start = 0;
        while (start <= text.size())
        {
            size_t end = text.find_first_of("\r\n", start);
            if (end == std::string_view::npos)
                end = text.size();
            result.emplace_back(text.substr(start, end - start));
            if (end == text.size())
                break;
            if (text[end] == '\r' && end + 1 < text.size() && text[end + 1] == '\n')
                end++;
            start = end + 1;
        }
        return result;
    }

    Utf8 escapeHtml(const std::string_view text, const bool attribute = false)
    {
        Utf8 result;
        result.reserve(text.size());
        for (const char c : text)
        {
            switch (c)
            {
                case '&':
                    result += "&amp;";
                    break;
                case '<':
                    result += "&lt;";
                    break;
                case '>':
                    result += "&gt;";
                    break;
                case '"':
                    if (attribute)
                        result += "&quot;";
                    else
                        result += c;
                    break;
                default:
                    result += c;
                    break;
            }
        }
        return result;
    }

    Utf8 makeAnchor(const std::string_view value)
    {
        Utf8 result;
        result.reserve(value.size() + 1);
        for (const char c : value)
        {
            if (std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-')
                result += c;
            else
                result += '_';
        }
        if (result.empty())
            result = "_";
        if (std::isdigit(static_cast<unsigned char>(result.front())))
            result.insert(result.begin(), '_');
        return result;
    }

    Utf8 lastNamePart(const std::string_view value)
    {
        const size_t pos = value.rfind('.');
        if (pos == std::string_view::npos)
            return Utf8(value);
        return Utf8(value.substr(pos + 1));
    }

    Utf8 displayNameFor(const std::string_view fullName, const DocItemKind kind)
    {
        if (kind == DocItemKind::Namespace)
            return Utf8(fullName);

        const size_t last = fullName.rfind('.');
        if (last == std::string_view::npos)
            return Utf8(fullName);
        const size_t previous = last ? fullName.rfind('.', last - 1) : std::string_view::npos;
        if (previous == std::string_view::npos)
            return Utf8(fullName);
        return Utf8(fullName.substr(previous + 1));
    }

    const char* itemKindName(const DocItemKind kind)
    {
        switch (kind)
        {
            case DocItemKind::Namespace:
                return "namespace";
            case DocItemKind::Struct:
                return "struct";
            case DocItemKind::Interface:
                return "interface";
            case DocItemKind::Enum:
                return "enum";
            case DocItemKind::Constant:
                return "const";
            case DocItemKind::Alias:
                return "type alias";
            case DocItemKind::Attribute:
                return "attr";
            case DocItemKind::Function:
                return "func";
        }
        SWC_UNREACHABLE();
    }

    const char* itemSectionName(const DocItemKind kind)
    {
        switch (kind)
        {
            case DocItemKind::Namespace:
                return "Namespaces";
            case DocItemKind::Struct:
                return "Structs";
            case DocItemKind::Interface:
                return "Interfaces";
            case DocItemKind::Enum:
                return "Enums";
            case DocItemKind::Constant:
                return "Constants";
            case DocItemKind::Alias:
                return "Type Aliases";
            case DocItemKind::Attribute:
                return "Attributes";
            case DocItemKind::Function:
                return "Functions";
        }
        SWC_UNREACHABLE();
    }

    int itemSortOrder(const DocItemKind kind)
    {
        return static_cast<int>(kind);
    }

    std::optional<DocItemKind> itemKind(const Symbol& symbol)
    {
        if (symbol.isNamespace())
            return DocItemKind::Namespace;
        if (symbol.isStruct())
            return DocItemKind::Struct;
        if (symbol.isInterface())
            return DocItemKind::Interface;
        if (symbol.isEnum())
            return DocItemKind::Enum;
        if (symbol.isConstant())
            return DocItemKind::Constant;
        if (symbol.isAlias())
            return DocItemKind::Alias;
        if (const auto* function = symbol.safeCast<SymbolFunction>())
            return function->isAttribute() ? DocItemKind::Attribute : DocItemKind::Function;
        return std::nullopt;
    }

    bool hasNoDocAttribute(const Symbol& symbol)
    {
        const Symbol* scan = &symbol;
        while (scan)
        {
            if (scan->hasAttributes() && scan->attributes().hasRtFlag(RtAttributeFlagsE::NoDoc))
                return true;
            scan = scan->ownerSymMap();
        }
        return false;
    }

    bool hasPublicAggregateOwner(const Symbol& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        while (owner)
        {
            if ((owner->isStruct() || owner->isInterface() || owner->isEnum()) && !owner->isPublic())
                return false;
            owner = owner->ownerSymMap();
        }
        return true;
    }

    bool isDocumentationSymbol(const CompilerInstance& compiler, const Symbol& symbol, const bool runtime)
    {
        if (symbol.isIgnored() || !symbol.decl() || !symbol.tokRef().isValid() || !symbol.idRef().isValid())
            return false;
        if (!itemKind(symbol).has_value() || hasNoDocAttribute(symbol))
            return false;

        const SourceFile* file = compiler.sourceViewFile(symbol);
        if (!file)
            return false;
        if (runtime)
            return file->isRuntime();
        if (!ModuleApi::isCurrentModuleSourceFile(*file))
            return false;
        return symbol.isPublic() && hasPublicAggregateOwner(symbol);
    }

    uint32_t countLineBreaks(const std::string_view text)
    {
        uint32_t result = 0;
        for (size_t i = 0; i < text.size(); ++i)
        {
            if (text[i] == '\n')
            {
                result++;
                continue;
            }
            if (text[i] == '\r')
            {
                result++;
                if (i + 1 < text.size() && text[i + 1] == '\n')
                    i++;
            }
        }
        return result;
    }

    bool commentStartsOnItsOwnLine(const SourceView& srcView, const Token& token)
    {
        const std::string_view source = srcView.stringView();
        size_t                 offset = std::min<size_t>(token.byteStart, source.size());
        while (offset && source[offset - 1] != '\r' && source[offset - 1] != '\n')
        {
            if (!std::isspace(static_cast<unsigned char>(source[offset - 1])))
                return false;
            offset--;
        }
        return true;
    }

    void appendNormalizedComment(std::vector<Utf8>& outLines, std::string_view text)
    {
        if (text.starts_with("//"))
        {
            text.remove_prefix(2);
            if (!text.empty() && text.front() == ' ')
                text.remove_prefix(1);
            outLines.emplace_back(text);
            return;
        }

        if (text.starts_with("/*"))
            text.remove_prefix(2);
        if (text.ends_with("*/"))
            text.remove_suffix(2);

        std::vector<Utf8> lines = splitLines(text);
        for (Utf8& line : lines)
        {
            std::string_view view = line;
            while (!view.empty() && (view.front() == ' ' || view.front() == '\t'))
                view.remove_prefix(1);
            if (!view.empty() && view.front() == '*')
            {
                view.remove_prefix(1);
                if (!view.empty() && view.front() == ' ')
                    view.remove_prefix(1);
            }
            outLines.emplace_back(view);
        }

        while (!outLines.empty() && trimView(outLines.front()).empty())
            outLines.erase(outLines.begin());
        while (!outLines.empty() && trimView(outLines.back()).empty())
            outLines.pop_back();
    }

    std::vector<Utf8> leadingCommentLines(TaskContext& ctx, const SourceFile& file, const AstNodeRef rootRef)
    {
        std::vector<Utf8> result;
        const Ast&        ast = file.ast();
        if (rootRef.isInvalid() || !ast.hasNode(rootRef))
            return result;

        const AstNode&    rootNode   = ast.node(rootRef);
        const SourceView& srcView    = ModuleApi::Export::moduleApiNodeSourceView(ctx, ast, rootRef);
        const TokenRef    startToken = ModuleApi::Export::moduleApiSnippetStartTokRef(ast, rootNode);
        if (!startToken.isValid() || startToken.get() >= srcView.numTokens() || startToken.get() + 1 >= srcView.triviaStart().size())
            return result;

        const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(startToken);
        bool hasComment                     = false;
        for (uint32_t i = triviaStart; i < triviaEnd; ++i)
        {
            const SourceTrivia& trivia = srcView.trivia()[i];
            if (trivia.tok.id == TokenId::Whitespace)
            {
                if (countLineBreaks(trivia.tok.string(srcView)) >= 2)
                {
                    result.clear();
                    hasComment = false;
                }
                continue;
            }

            if (trivia.tok.id != TokenId::CommentLine && trivia.tok.id != TokenId::CommentBlock)
                continue;
            if (!commentStartsOnItsOwnLine(srcView, trivia.tok))
            {
                result.clear();
                hasComment = false;
                continue;
            }

            appendNormalizedComment(result, trivia.tok.string(srcView));
            hasComment = true;
        }

        if (!hasComment)
            result.clear();
        return result;
    }

    std::vector<Utf8> trailingCommentLines(TaskContext& ctx, const SourceFile& file, const AstNodeRef declRef)
    {
        std::vector<Utf8> result;
        const Ast&        ast = file.ast();
        if (declRef.isInvalid() || !ast.hasNode(declRef))
            return result;

        const AstNode& node      = ast.node(declRef);
        const TokenRef endTokRef = node.tokRefEnd(ast);
        if (!endTokRef.isValid())
            return result;

        const SourceView& srcView = ModuleApi::Export::moduleApiNodeSourceView(ctx, ast, declRef);
        if (endTokRef.get() >= srcView.numTokens())
            return result;

        const Token&           token  = srcView.token(endTokRef);
        const std::string_view source = srcView.stringView();
        size_t                 start  = std::min<size_t>(ModuleApi::Export::sourceTokenByteEnd(srcView, token), source.size());
        size_t                 end    = source.find_first_of("\r\n", start);
        if (end == std::string_view::npos)
            end = source.size();

        const std::string_view suffix = source.substr(start, end - start);
        const size_t           line   = suffix.find("//");
        const size_t           block  = suffix.find("/*");
        size_t                 commentPos;
        if (line == std::string_view::npos)
            commentPos = block;
        else if (block == std::string_view::npos)
            commentPos = line;
        else
            commentPos = std::min(line, block);
        if (commentPos == std::string_view::npos)
            return result;

        appendNormalizedComment(result, suffix.substr(commentPos));
        return result;
    }

    std::vector<Utf8> symbolCommentLines(TaskContext& ctx, const Symbol& symbol, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef)
    {
        std::vector<Utf8> result;
        if (symbol.isConstant() || symbol.isAlias() || symbol.isVariable() || symbol.isEnumValue())
            result = trailingCommentLines(ctx, file, declRef);
        if (result.empty())
            result = leadingCommentLines(ctx, file, rootRef);
        return result;
    }

    AstNodeRef declarationBodyRef(const AstNode& node)
    {
        if (const auto* function = node.safeCast<AstFunctionDecl>())
            return function->nodeBodyRef;
        if (const auto* structDecl = node.safeCast<AstStructDecl>())
            return structDecl->nodeBodyRef;
        if (const auto* interfaceDecl = node.safeCast<AstInterfaceDecl>())
            return interfaceDecl->nodeBodyRef;
        if (const auto* enumDecl = node.safeCast<AstEnumDecl>())
            return enumDecl->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    Utf8 buildDisplaySignature(TaskContext& ctx, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef)
    {
        const Ast& ast = file.ast();
        if (declRef.isInvalid() || rootRef.isInvalid() || !ast.hasNode(declRef) || !ast.hasNode(rootRef))
            return {};

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!ModuleApi::Export::tryGetModuleApiSnippetOffsets(ctx, file, rootRef, startOffset, endOffset))
            return {};

        const SourceView& srcView = ModuleApi::Export::moduleApiNodeSourceView(ctx, ast, rootRef);
        const AstNodeRef  bodyRef = declarationBodyRef(ast.node(declRef));
        if (bodyRef.isValid() && ast.hasNode(bodyRef))
        {
            const AstNode& bodyNode = ast.node(bodyRef);
            if (bodyNode.tokRef().isValid())
            {
                const SourceView& bodyView = ModuleApi::Export::moduleApiNodeSourceView(ctx, ast, bodyRef);
                if (&bodyView == &srcView)
                    endOffset = ModuleApi::Export::sourceTokenByteStart(srcView, srcView.token(bodyNode.tokRef()));
            }
        }

        const std::string_view source = srcView.stringView();
        startOffset                   = std::min<uint32_t>(startOffset, static_cast<uint32_t>(source.size()));
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return {};

        Utf8 result = ModuleApi::Export::buildSanitizedModuleApiSnippet(ctx, file, rootRef, startOffset, source.substr(startOffset, endOffset - startOffset), "\n");
        result.trim();
        return result;
    }

    Utf8 sourceCategory(const CompilerInstance& compiler, const SourceFile& file, const bool runtime)
    {
        if (runtime || compiler.cmdLine().modulePath.empty())
            return {};

        const fs::path  sourceRoot = (compiler.cmdLine().modulePath / "src").lexically_normal();
        std::error_code ec;
        fs::path        relative = fs::relative(file.path().parent_path(), sourceRoot, ec);
        if (ec || relative.empty() || relative == ".")
            return {};

        const std::string value = relative.generic_string();
        if (value.starts_with(".."))
            return {};
        return Utf8(value);
    }

    void collectSymbolTree(std::vector<const Symbol*>& outSymbols, std::unordered_set<const Symbol*>& seen, const SymbolMap& symbolMap)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            if (!symbol || !seen.insert(symbol).second)
                continue;
            outSymbols.push_back(symbol);
            if (symbol->isSymMap())
                collectSymbolTree(outSymbols, seen, *symbol->asSymMap());
        }
    }

    void collectDocItems(TaskContext& ctx, std::vector<DocItem>& outItems, const bool runtime)
    {
        CompilerInstance&                 compiler = ctx.compiler();
        std::vector<const Symbol*>        symbols;
        std::unordered_set<const Symbol*> seen;
        if (compiler.symModule())
            collectSymbolTree(symbols, seen, *compiler.symModule());
        if (compiler.importRootNamespace())
            collectSymbolTree(symbols, seen, *compiler.importRootNamespace());

        std::unordered_map<Utf8, size_t> itemIndices;
        std::unordered_set<Utf8>         overloadKeys;
        for (const Symbol* symbol : symbols)
        {
            if (!symbol || !isDocumentationSymbol(compiler, *symbol, runtime))
                continue;

            const SourceFile* file = compiler.sourceViewFile(*symbol);
            SWC_ASSERT(file != nullptr);

            AstNodeRef declRef;
            if (!ModuleApi::Internal::tryFindNodeRef(file->ast(), symbol->decl(), declRef))
                continue;
            const AstNodeRef rootRef = ModuleApi::Internal::findExportDeclRoot(*file, declRef);
            if (rootRef.isInvalid())
                continue;

            const std::optional<DocItemKind> kind = itemKind(*symbol);
            SWC_ASSERT(kind.has_value());
            const Utf8 fullName = symbol->getFullScopedName(ctx);
            if (fullName.empty())
                continue;

            DocOverload overload;
            overload.symbol       = symbol;
            overload.file         = file;
            overload.signature    = buildDisplaySignature(ctx, *file, declRef, rootRef);
            overload.commentLines = symbolCommentLines(ctx, *symbol, *file, declRef, rootRef);
            overload.sourceLine   = symbol->codeRange(ctx).line + 1;

            Utf8 itemKey;
            itemKey.append(std::to_string(itemSortOrder(*kind)));
            itemKey += ":";
            itemKey += fullName;

            Utf8 overloadKey = itemKey;
            overloadKey += "\n";
            overloadKey += overload.signature;
            overloadKey += "\n";
            overloadKey.append(file->path().generic_string());
            overloadKey += ":";
            overloadKey.append(std::to_string(overload.sourceLine));
            if (!overloadKeys.insert(overloadKey).second)
                continue;

            const auto [it, inserted] = itemIndices.emplace(itemKey, outItems.size());
            if (inserted)
            {
                DocItem item;
                item.kind        = *kind;
                item.fullName    = fullName;
                item.displayName = displayNameFor(fullName, *kind);
                item.category    = sourceCategory(compiler, *file, runtime);
                outItems.push_back(std::move(item));
            }
            outItems[it->second].overloads.push_back(std::move(overload));
        }

        std::ranges::sort(outItems, [](const DocItem& lhs, const DocItem& rhs) {
            const int lhsOrder = itemSortOrder(lhs.kind);
            const int rhsOrder = itemSortOrder(rhs.kind);
            if (lhsOrder != rhsOrder)
                return lhsOrder < rhsOrder;
            if (lhs.category != rhs.category)
                return lhs.category < rhs.category;
            return lhs.fullName < rhs.fullName;
        });
    }

    Utf8 resolveReference(const RenderContext& renderCtx, const std::string_view name)
    {
        if (renderCtx.references)
        {
            const auto it = renderCtx.references->find(Utf8(name));
            if (it != renderCtx.references->end())
                return std::format("<a href=\"#{}\">{}</a>", it->second, escapeHtml(name));
        }

        if (name.starts_with("Swag."))
        {
            const Utf8 anchor = makeAnchor(name);
            return std::format("<a href=\"swag.runtime.html#{}\">{}</a>", anchor, escapeHtml(name));
        }
        return {};
    }

    Utf8 renderInline(const RenderContext& renderCtx, const std::string_view text)
    {
        Utf8   result;
        size_t pos = 0;
        while (pos < text.size())
        {
            if (text.substr(pos).starts_with("[["))
            {
                const size_t end = text.find("]]", pos + 2);
                if (end != std::string_view::npos)
                {
                    const std::string_view name = text.substr(pos + 2, end - pos - 2);
                    const Utf8             ref  = resolveReference(renderCtx, name);
                    if (!ref.empty())
                    {
                        result += ref;
                        pos = end + 2;
                        continue;
                    }
                }
            }

            if (text.substr(pos).starts_with("!["))
            {
                const size_t nameEnd = text.find(']', pos + 2);
                if (nameEnd != std::string_view::npos && nameEnd + 1 < text.size() && text[nameEnd + 1] == '(')
                {
                    const size_t linkEnd = text.find(')', nameEnd + 2);
                    if (linkEnd != std::string_view::npos)
                    {
                        const auto name = text.substr(pos + 2, nameEnd - pos - 2);
                        const auto link = text.substr(nameEnd + 2, linkEnd - nameEnd - 2);
                        result.append(std::format("<img src=\"{}\" alt=\"{}\">", escapeHtml(link, true), escapeHtml(name, true)));
                        pos = linkEnd + 1;
                        continue;
                    }
                }
            }

            if (text[pos] == '[')
            {
                const size_t nameEnd = text.find(']', pos + 1);
                if (nameEnd != std::string_view::npos && nameEnd + 1 < text.size() && text[nameEnd + 1] == '(')
                {
                    const size_t linkEnd = text.find(')', nameEnd + 2);
                    if (linkEnd != std::string_view::npos)
                    {
                        const auto name = text.substr(pos + 1, nameEnd - pos - 1);
                        const auto link = text.substr(nameEnd + 2, linkEnd - nameEnd - 2);
                        result.append(std::format("<a href=\"{}\">{}</a>", escapeHtml(link, true), escapeHtml(name)));
                        pos = linkEnd + 1;
                        continue;
                    }
                }
            }

            struct Marker
            {
                std::string_view open;
                std::string_view close;
                std::string_view htmlOpen;
                std::string_view htmlClose;
            };
            constexpr Marker markers[] = {
                {"***", "***", "<b><i>", "</i></b>"},
                {"**", "**", "<b>", "</b>"},
                {"~~", "~~", "<span class=\"strikethrough-text\">", "</span>"},
                {"`", "`", "<span class=\"code-inline\">", "</span>"},
            };

            bool matched = false;
            for (const Marker& marker : markers)
            {
                if (!text.substr(pos).starts_with(marker.open))
                    continue;
                const size_t end = text.find(marker.close, pos + marker.open.size());
                if (end == std::string_view::npos)
                    continue;

                result.append(marker.htmlOpen);
                result += escapeHtml(text.substr(pos + marker.open.size(), end - pos - marker.open.size()));
                result.append(marker.htmlClose);
                pos     = end + marker.close.size();
                matched = true;
                break;
            }
            if (matched)
                continue;

            if (text[pos] == '\'')
            {
                const size_t end = text.find('\'', pos + 1);
                if (end != std::string_view::npos && end > pos + 1)
                {
                    const std::string_view code = text.substr(pos + 1, end - pos - 1);
                    if (code.find_first_of(" \t\r\n") == std::string_view::npos)
                    {
                        result += "<span class=\"code-inline\">";
                        result += escapeHtml(code);
                        result += "</span>";
                        pos = end + 1;
                        continue;
                    }
                }
            }

            if (text[pos] == '*' && (pos + 1 >= text.size() || text[pos + 1] != '*'))
            {
                const size_t end = text.find('*', pos + 1);
                if (end != std::string_view::npos && end > pos + 1)
                {
                    result += "<i>";
                    result += escapeHtml(text.substr(pos + 1, end - pos - 1));
                    result += "</i>";
                    pos = end + 1;
                    continue;
                }
            }

            if (text[pos] == '\\' && pos + 1 < text.size())
            {
                result += escapeHtml(text.substr(pos + 1, 1));
                pos += 2;
                continue;
            }

            result += escapeHtml(text.substr(pos, 1));
            pos++;
        }
        return result;
    }

    Utf8 renderCodeBlock(TaskContext& ctx, const std::string_view code, const bool swagSyntax)
    {
        const Utf8 escaped = escapeHtml(code);
        Utf8       rendered;
        if (swagSyntax)
            rendered = SyntaxColorHelper::colorize(ctx, SyntaxColorMode::ForDoc, escaped.view(), true);
        else
            rendered = std::format("<span class=\"{}\">{}</span>", SYN_CODE, escaped);
        return std::format("<div class=\"code-block\">{}</div>\n", rendered);
    }

    bool isOrderedListLine(const std::string_view line)
    {
        const std::string_view value = trimView(line);
        size_t                 i     = 0;
        while (i < value.size() && std::isdigit(static_cast<unsigned char>(value[i])))
            i++;
        return i > 0 && i + 1 < value.size() && value[i] == '.' && value[i + 1] == ' ';
    }

    bool isTableSeparatorCell(std::string_view cell)
    {
        cell = trimView(cell);
        if (!cell.empty() && cell.front() == ':')
            cell.remove_prefix(1);
        if (!cell.empty() && cell.back() == ':')
            cell.remove_suffix(1);
        return cell.size() >= 3 && std::ranges::all_of(cell, [](const char c) { return c == '-'; });
    }

    std::vector<Utf8> splitTableRow(std::string_view line)
    {
        line = trimView(line);
        if (!line.empty() && line.front() == '|')
            line.remove_prefix(1);
        if (!line.empty() && line.back() == '|')
            line.remove_suffix(1);

        std::vector<Utf8> cells;
        size_t            start = 0;
        while (start <= line.size())
        {
            size_t end = line.find('|', start);
            if (end == std::string_view::npos)
                end = line.size();
            cells.emplace_back(trimView(line.substr(start, end - start)));
            if (end == line.size())
                break;
            start = end + 1;
        }
        return cells;
    }

    bool isMarkdownBlockStart(std::span<const Utf8> lines, const size_t index)
    {
        const std::string_view raw  = lines[index];
        const std::string_view line = trimView(raw);
        if (line.empty() || line == "---" || line.starts_with("```") || line.starts_with(">") || line.starts_with("# ") || line.starts_with("## ") || line.starts_with("### ") || line.starts_with("#### ") || line.starts_with("##### ") || line.starts_with("###### "))
            return true;
        if (raw.starts_with("    ") || raw.starts_with("\t"))
            return true;
        if (line.starts_with("* ") || line.starts_with("- ") || line.starts_with("+ ") || isOrderedListLine(line))
            return true;
        if (line.starts_with("<html>"))
            return true;
        return line.starts_with("|") && index + 1 < lines.size();
    }

    Utf8 renderMarkdownLines(const RenderContext& renderCtx, std::span<const Utf8> lines, const uint32_t headingOffset = 0)
    {
        Utf8   result;
        size_t index = 0;
        while (index < lines.size())
        {
            const std::string_view raw  = lines[index];
            const std::string_view line = trimView(raw);
            if (line.empty())
            {
                index++;
                continue;
            }

            if (line.starts_with("<html>"))
            {
                std::string_view first = line.substr(6);
                if (!first.empty())
                {
                    result.append(first);
                    result += "\n";
                }
                index++;
                while (index < lines.size())
                {
                    const std::string_view rawLine = lines[index++];
                    const size_t           endPos  = rawLine.find("</html>");
                    if (endPos != std::string_view::npos)
                    {
                        result.append(rawLine.substr(0, endPos));
                        result += "\n";
                        break;
                    }
                    result.append(rawLine);
                    result += "\n";
                }
                continue;
            }

            if (line.starts_with("```"))
            {
                const bool swagSyntax = line == "```swag";
                index++;
                Utf8 code;
                while (index < lines.size() && !trimView(lines[index]).starts_with("```"))
                {
                    code += lines[index++];
                    code += "\n";
                }
                if (index < lines.size())
                    index++;
                result += renderCodeBlock(*renderCtx.ctx, code, swagSyntax);
                continue;
            }

            if (raw.starts_with("    ") || raw.starts_with("\t"))
            {
                Utf8 code;
                while (index < lines.size())
                {
                    std::string_view codeLine = lines[index];
                    if (codeLine.starts_with("    "))
                        codeLine.remove_prefix(4);
                    else if (codeLine.starts_with("\t"))
                        codeLine.remove_prefix(1);
                    else
                        break;
                    code.append(codeLine);
                    code += "\n";
                    index++;
                }
                result += renderCodeBlock(*renderCtx.ctx, code, false);
                continue;
            }

            if (line == "---")
            {
                result += "<hr>\n";
                index++;
                continue;
            }

            if (line.front() == '#')
            {
                size_t level = 0;
                while (level < line.size() && line[level] == '#')
                    level++;
                if (level < line.size() && line[level] == ' ')
                {
                    const std::string_view title     = trimView(line.substr(level + 1));
                    const uint32_t         htmlLevel = std::clamp<uint32_t>(static_cast<uint32_t>(level) + headingOffset, 1, 6);
                    result.append(std::format("<h{} id=\"{}\">{}</h{}>\n", htmlLevel, makeAnchor(title), renderInline(renderCtx, title), htmlLevel));
                    index++;
                    continue;
                }
            }

            if (line.starts_with(">"))
            {
                std::vector<Utf8> quoteLines;
                while (index < lines.size())
                {
                    std::string_view quoteLine = trimView(lines[index]);
                    if (!quoteLine.starts_with(">"))
                        break;
                    quoteLine.remove_prefix(1);
                    if (!quoteLine.empty() && quoteLine.front() == ' ')
                        quoteLine.remove_prefix(1);
                    quoteLines.emplace_back(quoteLine);
                    index++;
                }

                std::string_view kind;
                std::string_view defaultTitle;
                Utf8             icon;
                Utf8             title;
                if (!quoteLines.empty())
                {
                    struct QuoteKind
                    {
                        const char* marker;
                        const char* css;
                        const char* title;
                        const Utf8* icon;
                        const Utf8* configuredTitle;
                    };
                    const PageOptions& options = *renderCtx.options;
                    const QuoteKind    kinds[] = {
                        {"NOTE:", "note", "Note", &options.quoteIconNote, &options.quoteTitleNote},
                        {"TIP:", "tip", "Tip", &options.quoteIconTip, &options.quoteTitleTip},
                        {"WARNING:", "warning", "Warning", &options.quoteIconWarning, &options.quoteTitleWarning},
                        {"ATTENTION:", "attention", "Attention", &options.quoteIconAttention, &options.quoteTitleAttention},
                        {"EXAMPLE:", "example", "Example", &options.quoteIconExample, &options.quoteTitleExample},
                    };
                    for (const QuoteKind& candidate : kinds)
                    {
                        if (!trimView(quoteLines.front()).starts_with(candidate.marker))
                            continue;
                        kind                   = candidate.css;
                        defaultTitle           = candidate.title;
                        icon                   = *candidate.icon;
                        title                  = candidate.configuredTitle->empty() ? Utf8(defaultTitle) : *candidate.configuredTitle;
                        std::string_view first = trimView(quoteLines.front());
                        first.remove_prefix(std::strlen(candidate.marker));
                        quoteLines.front() = trimCopy(first);
                        break;
                    }
                }

                if (kind.empty())
                {
                    result += "<div class=\"blockquote blockquote-default\">\n";
                }
                else
                {
                    result.append(std::format("<div class=\"blockquote blockquote-{}\">\n", kind));
                    result += "<div class=\"blockquote-title-block\">";
                    if (!icon.empty())
                    {
                        result += icon;
                        result += " ";
                    }
                    result.append(std::format("<span class=\"blockquote-title\">{}</span></div>\n", escapeHtml(title)));
                }
                result += renderMarkdownLines(renderCtx, quoteLines, headingOffset);
                result += "</div>\n";
                continue;
            }

            if (line.starts_with("|") && index + 1 < lines.size())
            {
                const std::vector<Utf8> header    = splitTableRow(line);
                const std::vector<Utf8> separator = splitTableRow(lines[index + 1]);
                const bool              isTable   = !header.empty() &&
                                     separator.size() == header.size() &&
                                     std::ranges::all_of(separator, [](const Utf8& cell) { return isTableSeparatorCell(cell); });
                if (isTable)
                {
                    result += "<table class=\"table-markdown\">\n<tr>";
                    for (const Utf8& cell : header)
                        result.append(std::format("<th>{}</th>", renderInline(renderCtx, cell)));
                    result += "</tr>\n";
                    index += 2;
                    while (index < lines.size() && trimView(lines[index]).starts_with("|"))
                    {
                        std::vector<Utf8> cells = splitTableRow(lines[index++]);
                        cells.resize(header.size());
                        result += "<tr>";
                        for (const Utf8& cell : cells)
                            result.append(std::format("<td>{}</td>", renderInline(renderCtx, cell)));
                        result += "</tr>\n";
                    }
                    result += "</table>\n";
                    continue;
                }
            }

            if (line.starts_with("* ") || line.starts_with("- ") || isOrderedListLine(line))
            {
                const bool ordered = isOrderedListLine(line);
                result += ordered ? "<ol>\n" : "<ul>\n";
                while (index < lines.size())
                {
                    std::string_view item = trimView(lines[index]);
                    if (ordered)
                    {
                        if (!isOrderedListLine(item))
                            break;
                        item.remove_prefix(item.find('.') + 1);
                    }
                    else
                    {
                        if (!item.starts_with("* ") && !item.starts_with("- "))
                            break;
                        item.remove_prefix(1);
                    }
                    item = trimView(item);
                    result.append(std::format("<li>{}</li>\n", renderInline(renderCtx, item)));
                    index++;
                }
                result += ordered ? "</ol>\n" : "</ul>\n";
                continue;
            }

            if (line.starts_with("+ "))
            {
                while (index < lines.size() && trimView(lines[index]).starts_with("+ "))
                {
                    std::string_view title = trimView(lines[index]);
                    title.remove_prefix(2);
                    result.append(std::format("<div class=\"description-list-title\"><p>{}</p></div>\n", renderInline(renderCtx, title)));
                    index++;

                    std::vector<Utf8> description;
                    while (index < lines.size() && (lines[index].starts_with("    ") || lines[index].starts_with("\t") || trimView(lines[index]).empty()))
                    {
                        std::string_view descriptionLine = lines[index++];
                        if (descriptionLine.starts_with("    "))
                            descriptionLine.remove_prefix(4);
                        else if (descriptionLine.starts_with("\t"))
                            descriptionLine.remove_prefix(1);
                        description.emplace_back(descriptionLine);
                    }
                    result += "<div class=\"description-list-block\">\n";
                    result += renderMarkdownLines(renderCtx, description, headingOffset);
                    result += "</div>\n";
                }
                continue;
            }

            Utf8 paragraph;
            while (index < lines.size())
            {
                if (!paragraph.empty() && isMarkdownBlockStart(lines, index))
                    break;
                const std::string_view paragraphLine = trimView(lines[index]);
                if (paragraphLine.empty())
                    break;
                if (!paragraph.empty())
                    paragraph += " ";
                paragraph.append(paragraphLine);
                index++;
            }
            if (!paragraph.empty())
                result.append(std::format("<p>{}</p>\n", renderInline(renderCtx, paragraph)));
            else
                index++;
        }
        return result;
    }

    std::vector<Utf8> firstParagraph(std::span<const Utf8> lines)
    {
        std::vector<Utf8> result;
        for (const Utf8& line : lines)
        {
            if (trimView(line).empty())
                break;
            result.push_back(line);
        }
        return result;
    }

    Utf8 codeHtml(TaskContext& ctx, const std::string_view code)
    {
        if (code.empty())
            return {};
        return renderCodeBlock(ctx, code, true);
    }

    void addReference(std::unordered_map<Utf8, Utf8>& references, std::unordered_set<Utf8>& ambiguous, const Utf8& name, const Utf8& anchor)
    {
        if (name.empty() || ambiguous.contains(name))
            return;
        const auto [it, inserted] = references.emplace(name, anchor);
        if (inserted || it->second == anchor)
            return;
        references.erase(it);
        ambiguous.insert(name);
    }

    void buildReferences(ApiDocument& document)
    {
        std::unordered_set<Utf8> ambiguous;
        for (const DocItem& item : document.items)
        {
            const Utf8 anchor = makeAnchor(item.fullName);
            addReference(document.references, ambiguous, item.fullName, anchor);
            addReference(document.references, ambiguous, item.displayName, anchor);
            addReference(document.references, ambiguous, lastNamePart(item.fullName), anchor);
        }
    }

    Utf8 sourceLink(const CompilerInstance& compiler, const DocOverload& overload, const bool runtime)
    {
        Utf8 repoPath = fromRuntimeString(compiler.buildCfg().repoPath);
        if (runtime)
            repoPath = "https://github.com/swag-lang/swc/blob/master/bin/runtime";
        if (repoPath.empty() || !overload.file)
            return {};

        fs::path relative = overload.file->path().filename();
        if (!runtime && !compiler.cmdLine().modulePath.empty())
        {
            std::error_code ec;
            const fs::path  candidate = fs::relative(overload.file->path(), compiler.cmdLine().modulePath, ec);
            if (!ec && !candidate.empty() && !candidate.generic_string().starts_with(".."))
                relative = candidate;
        }

        Utf8 result = repoPath;
        if (!result.empty() && result.back() != '/')
            result += "/";
        result.append(relative.generic_string());
        result.append(std::format("#L{}", overload.sourceLine));
        return result;
    }

    bool canDocumentMember(const CompilerInstance& compiler, const Symbol& symbol, const bool runtime)
    {
        if (symbol.isIgnored() || hasNoDocAttribute(symbol) || !symbol.decl() || !symbol.tokRef().isValid())
            return false;
        const SourceFile* file = compiler.sourceViewFile(symbol);
        if (!file)
            return false;
        if (runtime)
            return file->isRuntime();
        return ModuleApi::isCurrentModuleSourceFile(*file) && symbol.isPublic();
    }

    std::vector<Utf8> memberCommentLines(TaskContext& ctx, const Symbol& symbol)
    {
        const SourceFile* file = ctx.compiler().sourceViewFile(symbol);
        if (!file)
            return {};
        AstNodeRef declRef;
        if (!ModuleApi::Internal::tryFindNodeRef(file->ast(), symbol.decl(), declRef))
            return {};
        const AstNodeRef rootRef = ModuleApi::Internal::findExportDeclRoot(*file, declRef);
        return symbolCommentLines(ctx, symbol, *file, declRef, rootRef);
    }

    void renderMemberTable(Utf8& content, const RenderContext& renderCtx, const Symbol& owner, const bool runtime)
    {
        if (!owner.isSymMap())
            return;

        std::vector<const Symbol*> members;
        owner.asSymMap()->getAllSymbols(members);

        struct MemberRow
        {
            const Symbol*     symbol = nullptr;
            Utf8              name;
            Utf8              type;
            Utf8              anchor;
            std::vector<Utf8> commentLines;
        };
        std::vector<MemberRow> fields;
        std::vector<MemberRow> functions;

        for (const Symbol* member : members)
        {
            if (!member || !canDocumentMember(renderCtx.ctx->compiler(), *member, runtime))
                continue;

            MemberRow row;
            row.symbol       = member;
            row.name         = Utf8(member->name(*renderCtx.ctx));
            row.commentLines = memberCommentLines(*renderCtx.ctx, *member);
            if (member->typeRef().isValid())
                row.type = member->typeInfo(*renderCtx.ctx).toFullName(*renderCtx.ctx);

            if (member->isFunction())
            {
                const Utf8 fullName = member->getFullScopedName(*renderCtx.ctx);
                row.anchor          = makeAnchor(fullName);
                functions.push_back(std::move(row));
            }
            else if ((owner.isEnum() && member->isEnumValue()) ||
                     ((owner.isStruct() || owner.isInterface()) && (member->isVariable() || member->isConstant())))
            {
                fields.push_back(std::move(row));
            }
        }

        const auto rowLess = [](const MemberRow& lhs, const MemberRow& rhs) {
            return lhs.name < rhs.name;
        };
        std::ranges::sort(fields, rowLess);
        std::ranges::sort(functions, rowLess);

        const auto outputRows = [&](const char* title, const std::vector<MemberRow>& rows, const bool links) {
            if (rows.empty())
                return;
            content.append(std::format("<h3>{}</h3>\n<table class=\"table-enumeration\">\n", title));
            for (const MemberRow& row : rows)
            {
                content += "<tr><td class=\"code-type\">";
                if (links)
                    content.append(std::format("<a href=\"#{}\">{}</a>", row.anchor, escapeHtml(row.name)));
                else
                    content += escapeHtml(row.name);
                content += "</td>";
                if (!links)
                    content.append(std::format("<td class=\"code-type\">{}</td>", escapeHtml(row.type)));
                const std::vector<Utf8> summary = firstParagraph(row.commentLines);
                content.append(std::format("<td>{}</td></tr>\n", renderMarkdownLines(renderCtx, summary)));
            }
            content += "</table>\n";
        };

        outputRows(owner.isEnum() ? "Values" : "Fields", fields, false);
        outputRows("Functions", functions, true);
    }

    void renderApiDocument(TaskContext& ctx, ApiDocument& document, const PageOptions& options, const bool runtime)
    {
        buildReferences(document);
        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = &document.references,
        };

        Utf8 lastSection;
        Utf8 lastCategory;
        for (const DocItem& item : document.items)
        {
            const Utf8 section = itemSectionName(item.kind);
            if (section != lastSection)
            {
                document.toc.append(std::format("<h3>{}</h3>\n", section));
                lastSection = section;
                lastCategory.clear();
            }
            if (!item.category.empty() && item.category != lastCategory)
            {
                document.toc.append(std::format("<h4>{}</h4>\n", escapeHtml(item.category)));
                lastCategory = item.category;
            }
            if (lastCategory != item.category && item.category.empty())
                lastCategory.clear();

            document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", makeAnchor(item.fullName), escapeHtml(item.displayName)));
        }

        document.content += "<h1>Content</h1>\n";
        for (const DocItem& item : document.items)
        {
            if (item.overloads.empty())
                continue;

            const DocOverload& first = item.overloads.front();
            const Utf8         link  = sourceLink(ctx.compiler(), first, runtime);

            document.content += "<table class=\"api-item\"><tr><td>";
            document.content.append(std::format("<span id=\"{}\"><span class=\"api-item-title-kind\">{}</span> <span class=\"api-item-title-strong\">{}</span></span>", makeAnchor(item.fullName), itemKindName(item.kind), escapeHtml(item.displayName)));
            document.content += "</td>";
            if (!link.empty())
                document.content.append(std::format("<td class=\"api-item-title-src-ref\"><a href=\"{}\">[src]</a></td>", escapeHtml(link, true)));
            document.content += "</tr></table>\n";

            for (const DocOverload& overload : item.overloads)
            {
                if (!overload.commentLines.empty())
                    document.content += renderMarkdownLines(renderCtx, overload.commentLines);
                if (!overload.signature.empty() && item.kind != DocItemKind::Namespace)
                    document.content += codeHtml(ctx, overload.signature);
            }

            renderMemberTable(document.content, renderCtx, *first.symbol, runtime);
        }
    }

    Utf8 defaultModuleDocComment(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::Module))
                continue;

            std::string_view source = file->sourceView();
            source                  = trimView(source);
            std::vector<Utf8> result;
            if (source.starts_with("/*"))
            {
                const size_t end = source.find("*/", 2);
                if (end != std::string_view::npos)
                    appendNormalizedComment(result, source.substr(0, end + 2));
            }
            else
            {
                for (const Utf8& line : splitLines(source))
                {
                    const std::string_view view = trimView(line);
                    if (!view.starts_with("//"))
                        break;
                    appendNormalizedComment(result, view);
                }
            }

            Utf8 comment;
            for (const Utf8& line : result)
            {
                comment += line;
                comment += "\n";
            }
            return comment;
        }
        return {};
    }

    Utf8 documentationStyles()
    {
        Utf8 result = R"(/*
 * Static stylesheet generated by swc doc.
 * The documentation intentionally needs no script or server-side runtime.
 */

:root {
    color-scheme: light;
    --swag-black: #050505;
    --swag-yellow: #f7f900;
    --swag-link: #1677c8;
    --swag-line: #d7d7d7;
    --swag-soft: #f3f3f3;
    --swag-header-height: 74px;
}

* {
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    margin: 0;
    color: #222;
    background: #fff;
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
    line-height: 1.45;
}

.site-header {
    position: sticky;
    z-index: 10;
    top: 0;
    min-height: var(--swag-header-height);
    color: #fff;
    background: var(--swag-black);
    border-bottom: 3px solid var(--swag-yellow);
}

.site-nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 28px;
    width: min(1200px, calc(100% - 32px));
    min-height: var(--swag-header-height);
    margin: 0 auto;
}

.site-brand {
    color: var(--swag-yellow);
    font-size: 1.45rem;
    font-weight: 800;
    letter-spacing: .14em;
    text-decoration: none;
}

.site-links {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px 22px;
}

.site-links a {
    color: #fff;
    text-decoration: none;
}

.site-links a:hover,
.site-links a:focus-visible {
    color: var(--swag-yellow);
}

.container {
    display: grid;
    grid-template-columns: minmax(230px, 330px) minmax(0, 1fr);
    gap: 34px;
    width: min(1500px, calc(100% - 32px));
    margin: 0 auto;
}

.container.single-page {
    display: block;
}

.left {
    position: sticky;
    top: var(--swag-header-height);
    height: calc(100vh - var(--swag-header-height));
    overflow-y: auto;
    border-right: 1px solid var(--swag-line);
}

.left-page {
    padding: 24px 24px 40px 4px;
}

.left h2 {
    margin-top: 0;
}

.left h3 {
    margin: 28px 0 8px;
    padding: 7px 9px;
    color: #fff;
    background: var(--swag-black);
}

.left h4 {
    margin: 18px 0 6px;
}

.left ul {
    margin: 0;
    padding-left: 14px;
    list-style: none;
}

.left li {
    margin: 3px 0;
}

.right {
    min-width: 0;
}

.right-page {
    width: min(100%, 1024px);
    margin: 0 auto;
    padding: 30px 10px 48px;
}

.single-page .right-page {
    padding-top: 34px;
}

.right h1 {
    margin: 32px 0 48px;
    font-size: clamp(2rem, 5vw, 3rem);
    line-height: 1.1;
}

.right h2 {
    margin-top: 42px;
}

.right hr {
    margin: 48px 0;
    border: 0;
    border-top: 1px solid var(--swag-line);
}

[id] {
    scroll-margin-top: calc(var(--swag-header-height) + 16px);
}

.container a {
    color: var(--swag-link);
}

.container a:hover {
    text-decoration: underline;
}

.container img {
    max-width: 100%;
    height: auto;
}

.no-decoration,
.round-button a,
.left a,
.table-enumeration a {
    text-decoration: none;
}

.round-button {
    display: inline-block;
    margin: 10px 5px;
    padding: 10px 14px;
    text-align: center;
    border: 1px solid #777;
    border-radius: 5px;
}

.strikethrough-text {
    text-decoration: line-through;
}

.swag-watermark {
    margin-top: 40px;
    color: #666;
    font-size: 80%;
    text-align: right;
}

.swag-watermark a {
    color: inherit;
    text-decoration: none;
}

.blockquote {
    margin: 20px;
    padding: 12px 14px;
    border: 1px solid;
    border-radius: 5px;
}

.blockquote-default {
    background: #ffffe0;
    border-color: orange;
    border-left-width: 6px;
}

.blockquote-note {
    background: #cdeefd;
    border-color: #adcedd;
}

.blockquote-tip {
    background: #dcefdc;
    border-color: #bccfbc;
}

.blockquote-warning {
    background: #ffddd3;
    border-color: #dfbdb3;
}

.blockquote-attention {
    background: #fddad8;
    border-color: #ddbab8;
}

.blockquote-example {
    border: 2px solid var(--swag-line);
}

.blockquote-title-block {
    margin-bottom: 10px;
}

.blockquote-title {
    font-weight: 700;
}

.description-list-title {
    font-weight: 700;
    font-style: italic;
}

.description-list-block {
    margin-left: 30px;
}

.container table {
    max-width: 100%;
    margin: 20px 0;
    border: 1px solid var(--swag-line);
    border-collapse: collapse;
    font-size: 90%;
}

.container td,
.container th {
    min-width: 100px;
    padding: 7px;
    border: 1px solid var(--swag-line);
}

.container th {
    background: #eee;
}

.table-markdown {
    width: 100%;
}

table.api-item {
    width: 100%;
    margin: 70px 0 0;
    color: #fff;
    background: var(--swag-black);
    border-collapse: separate;
    font-size: 110%;
}

.api-item td {
    border: 0;
}

.api-item td:first-child {
    width: 66%;
}

.api-item-title-src-ref {
    text-align: right;
}

.api-item-title-src-ref a {
    color: inherit;
}

.api-item-title-kind {
    font-size: 80%;
    font-weight: 400;
}

.api-item-title-strong {
    font-weight: 700;
}

.table-enumeration {
    width: 100%;
}

.table-enumeration td:first-child {
    white-space: nowrap;
    background: #f8f8f8;
}

.table-enumeration td:last-child {
    width: 100%;
}

.table-enumeration td.code-type {
    background: #eee;
}

.code-inline {
    display: inline-block;
    padding: 0 7px;
    background: #eee;
    border: 1px dotted #ccc;
    border-radius: 5px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}

.code-block {
    margin: 20px 0;
    padding: 12px;
    overflow-x: auto;
    background: var(--swag-soft);
    border: 1px solid var(--swag-line);
    border-radius: 5px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    white-space: pre;
}

.code-block a {
    color: inherit;
}

.SCmt { color: #6a9955; }
.SCmp, .SAtr { color: #777; }
.SFct { color: #c54f00; }
.SCst { color: #168f7d; }
.SItr { color: #8a7600; }
.STpe { color: #a66c00; }
.SKwd { color: #286fa8; }
.SLgc { color: #8e4d99; }
.SNum { color: #4d7a45; }
.SStr { color: #a64f38; }
.SInv { color: #d22; }
.SBcR { color: #817c31; }
.SCde { color: var(--swag-code-default, #222); }

@media (max-width: 780px) {
    :root {
        --swag-header-height: 112px;
    }

    .site-nav {
        align-items: flex-start;
        padding: 14px 0;
    }

    .site-links {
        gap: 6px 14px;
    }

    .container {
        display: block;
    }

    .left {
        position: static;
        width: 100%;
        height: auto;
        border-right: 0;
        border-bottom: 1px solid var(--swag-line);
    }

    .left-page {
        padding-right: 4px;
    }

    .right-page {
        padding-right: 0;
        padding-left: 0;
    }
}

@media (max-width: 480px) {
    :root {
        --swag-header-height: 146px;
    }

    .site-nav {
        display: block;
    }

    .site-brand {
        display: inline-block;
        margin-bottom: 10px;
    }

    .site-links {
        justify-content: flex-start;
    }

    .blockquote {
        margin-right: 0;
        margin-left: 0;
    }

    .container table {
        display: block;
        overflow-x: auto;
    }
}
)";
        return result;
    }

    Utf8 constructPage(const PageOptions& options, const std::string_view toc, const std::string_view content, const bool pages)
    {
        Utf8 result = std::format("<!DOCTYPE html>\n<html lang=\"en\" style=\"--swag-code-default: #{:06x}\">\n<head>\n<meta charset=\"UTF-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n", options.syntaxDefaultColor & 0x00FFFFFF);
        if (!options.titleContent.empty())
            result.append(std::format("<title>{}</title>\n", escapeHtml(options.titleContent)));
        if (!options.icon.empty())
            result.append(std::format("<link rel=\"icon\" type=\"image/x-icon\" href=\"{}\">\n", escapeHtml(options.icon, true)));
        if (!options.css.empty())
            result.append(std::format("<link rel=\"stylesheet\" type=\"text/css\" href=\"{}\">\n", escapeHtml(options.css, true)));
        result += "</head>\n<body>\n";
        result += R"(<header class="site-header">
<nav class="site-nav" aria-label="Main navigation">
<a class="site-brand" href="index.html">SWAG</a>
<div class="site-links">
<a href="index.html">Home</a>
<a href="language.html">Documentation</a>
<a href="swag.runtime.html">Runtime</a>
<a href="std.html">Std</a>
<a href="https://www.youtube.com/channel/UC9dkBu1nNfJDxUML7r7QH1Q">YouTube</a>
<a href="https://github.com/swag-lang/swc">GitHub</a>
</div>
</nav>
</header>
)";
        result += pages ? "<main class=\"container single-page\">\n" : "<main class=\"container\">\n";
        if (!pages)
        {
            result += "<aside class=\"left\"><div class=\"left-page\">\n";
            result.append(toc);
            result += "</div></aside>\n";
        }
        result += "<section class=\"right\"><article class=\"right-page\">\n";
        result.append(content);
        if (options.hasSwagWatermark)
            result.append(std::format("<div class=\"swag-watermark\">Generated with <a href=\"https://github.com/swag-lang/swc\">swc</a> {}.{}.{}</div>\n", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
        result += "</article></section>\n</main>\n";
        result += "</body>\n</html>\n";
        return result;
    }

    Result reportDocDirectoryError(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_doc_dir_create_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result reportDocFileError(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_doc_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result ensureOutputDirectory(TaskContext& ctx, const fs::path& path)
    {
        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
            return reportDocDirectoryError(ctx, path, FileSystem::normalizeSystemMessage(ec));
        return Result::Continue;
    }

    Result writeDocumentationFile(TaskContext& ctx, const fs::path& path, const std::string_view content)
    {
        if (!ctx.cmdLine().outputDoc)
            return Result::Continue;

        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFile(path, content.data(), content.size(), error) != Result::Continue)
            return reportDocFileError(ctx, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    Result writeDocumentationStyles(TaskContext& ctx, const PageOptions& options)
    {
        if (!ctx.cmdLine().outputDoc)
            return Result::Continue;

        const fs::path outputDir = DocGenerator::outputDirectory(ctx.compiler()).lexically_normal();
        const fs::path cssPath(options.css.c_str());
        if (cssPath.is_absolute() || options.css.contains("://"))
            return reportDocFileError(ctx, cssPath, "the stylesheet path must be relative to the documentation output directory");

        const fs::path path     = (outputDir / cssPath).lexically_normal();
        const fs::path relative = path.lexically_relative(outputDir);
        if (relative.empty() || (relative.begin() != relative.end() && *relative.begin() == ".."))
            return reportDocFileError(ctx, cssPath, "the stylesheet path must stay inside the documentation output directory");

        const std::scoped_lock lock(g_StylesheetMutex);
        SWC_RESULT(ensureOutputDirectory(ctx, path.parent_path()));
        return writeDocumentationFile(ctx, path, documentationStyles());
    }

    Utf8 defaultOutputBaseName(const CompilerInstance& compiler, const PageOptions& options)
    {
        if (!options.outputName.empty())
            return options.outputName;

        if (!compiler.cmdLine().workspacePath.empty() && !compiler.cmdLine().modulePath.empty())
        {
            Utf8 result = compiler.cmdLine().workspacePath.filename();
            result += ".";
            result.append(compiler.cmdLine().modulePath.filename().string());
            return result;
        }

        return defaultArtifactName(compiler.cmdLine());
    }

    fs::path outputFilePath(const CompilerInstance& compiler, const PageOptions& options)
    {
        Utf8 baseName = defaultOutputBaseName(compiler, options);
        baseName.make_lower();
        baseName += ".html";
        fs::path result = DocGenerator::outputDirectory(compiler) / fs::path(baseName.c_str());
        return result.lexically_normal();
    }

    Result generateApi(TaskContext& ctx, const PageOptions& options, const bool runtime, fs::path& outPath)
    {
        ApiDocument document;
        collectDocItems(ctx, document.items, runtime);
        renderApiDocument(ctx, document, options, runtime);

        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = &document.references,
        };

        Utf8 content;
        content.append(std::format("<h1>{}</h1>\n", escapeHtml(options.titleContent)));
        if (!runtime)
        {
            const Utf8 moduleComment = defaultModuleDocComment(ctx.compiler());
            if (!moduleComment.empty())
            {
                const std::vector<Utf8> lines = splitLines(moduleComment);
                content += renderMarkdownLines(renderCtx, lines);
            }
        }
        content += document.content;

        Utf8 toc;
        toc.append(std::format("<h2>{}</h2>\n", escapeHtml(options.titleToc)));
        toc += document.toc;

        outPath         = outputFilePath(ctx.compiler(), options);
        const Utf8 page = constructPage(options, toc, content, false);
        return writeDocumentationFile(ctx, outPath, page);
    }

    Utf8 correctTitle(Utf8 title)
    {
        std::ranges::replace(title, '_', ' ');
        const std::unordered_set<std::string_view> exceptions = {"and", "or", "in", "the", "of", "a", "an", "but", "for", "nor", "on", "at", "by", "with", "to"};

        std::vector<Utf8>  words;
        std::istringstream stream(title);
        std::string        word;
        while (stream >> word)
            words.emplace_back(word);

        Utf8 result;
        for (size_t i = 0; i < words.size(); ++i)
        {
            Utf8 value = words[i];
            value.make_lower();
            if (i == 0 || i + 1 == words.size() || !exceptions.contains(value.view()))
                value.front() = static_cast<char>(std::toupper(static_cast<unsigned char>(value.front())));
            if (!result.empty())
                result += " ";
            result += value;
        }
        return result;
    }

    Result readDocumentationSource(TaskContext& ctx, const fs::path& path, std::string& outText)
    {
        FileSystem::IoErrorInfo error;
        if (FileSystem::readTextFile(path, outText, error) != Result::Continue)
            return reportDocFileError(ctx, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    Utf8 renderExampleSource(TaskContext& ctx, const RenderContext& renderCtx, const std::string_view source)
    {
        const std::vector<Utf8> lines = splitLines(source);
        Utf8                    result;
        size_t                  index = 0;
        while (index < lines.size())
        {
            Utf8 code;
            while (index < lines.size() && !trimView(lines[index]).starts_with("/**"))
            {
                code += lines[index++];
                code += "\n";
            }
            result += renderCodeBlock(ctx, code, true);
            if (index == lines.size())
                break;

            index++;
            std::vector<Utf8> comment;
            while (index < lines.size() && !trimView(lines[index]).starts_with("*/"))
                comment.push_back(lines[index++]);
            if (index < lines.size())
                index++;
            result += renderMarkdownLines(renderCtx, comment, 2);
        }
        return result;
    }

    std::vector<const SourceFile*> moduleSourceFiles(const CompilerInstance& compiler)
    {
        std::vector<const SourceFile*> result;
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->hasFlag(FileFlagsE::ModuleSrc))
                result.push_back(file);
        }
        std::ranges::sort(result, [](const SourceFile* lhs, const SourceFile* rhs) { return lhs->path().filename().string() < rhs->path().filename().string(); });
        return result;
    }

    Result generateExamples(TaskContext& ctx, PageOptions options, fs::path& outPath)
    {
        if (options.titleContent.empty())
            options.titleContent = "Swag Examples";
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        Utf8 toc     = std::format("<h2>{}</h2>\n<ul>\n", escapeHtml(options.titleToc));
        Utf8 content = std::format("<h1>{}</h1>\n", escapeHtml(options.titleContent));

        uint32_t currentLevel = 1;
        for (const SourceFile* file : moduleSourceFiles(ctx.compiler()))
        {
            Utf8 stem = file->path().stem().string();
            if (stem.size() < 9 ||
                !std::isdigit(static_cast<unsigned char>(stem[0])) ||
                !std::isdigit(static_cast<unsigned char>(stem[1])) ||
                !std::isdigit(static_cast<unsigned char>(stem[2])) ||
                stem[3] != '_' ||
                !std::isdigit(static_cast<unsigned char>(stem[4])) ||
                !std::isdigit(static_cast<unsigned char>(stem[5])) ||
                !std::isdigit(static_cast<unsigned char>(stem[6])) ||
                stem[7] != '_')
                continue;

            const uint32_t level = stem.substr(4, 3) == "000" ? 1 : 2;
            while (currentLevel < level)
            {
                toc += "<ul>\n";
                currentLevel++;
            }
            while (currentLevel > level)
            {
                toc += "</ul>\n";
                currentLevel--;
            }

            const Utf8 title  = correctTitle(stem.substr(8));
            const Utf8 anchor = makeAnchor(file->name());
            toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", anchor, escapeHtml(title)));
            content.append(std::format("<h{} id=\"{}\">{}</h{}>\n", level + 1, anchor, escapeHtml(title), level + 1));

            if (file->path().extension() == ".md")
                content += renderMarkdownLines(renderCtx, splitLines(file->sourceView()), level + 1);
            else
                content += renderExampleSource(ctx, renderCtx, file->sourceView());
        }
        while (currentLevel > 1)
        {
            toc += "</ul>\n";
            currentLevel--;
        }
        toc += "</ul>\n";

        outPath         = outputFilePath(ctx.compiler(), options);
        const Utf8 page = constructPage(options, toc, content, false);
        return writeDocumentationFile(ctx, outPath, page);
    }

    Result appendAdditionalPages(TaskContext& ctx, const PageOptions& options, std::vector<fs::path>& paths)
    {
        if (options.morePages.empty())
            return Result::Continue;

        size_t start = 0;
        while (start <= options.morePages.size())
        {
            size_t end = options.morePages.find(';', start);
            if (end == Utf8::npos)
                end = options.morePages.size();
            const std::string_view value = trimView(options.morePages.subView(start, end - start));
            if (!value.empty())
            {
                fs::path path(value);
                if (path.is_relative())
                    path = ctx.compiler().cmdLine().modulePath / path;

                Utf8 because;
                if (FileSystem::resolveExistingFile(path, because) != Result::Continue)
                    return reportDocFileError(ctx, path, because);
                paths.push_back(path);
            }
            if (end == options.morePages.size())
                break;
            start = end + 1;
        }
        return Result::Continue;
    }

    Result collectPageSourcePaths(TaskContext& ctx, std::vector<fs::path>& paths)
    {
        const fs::path  sourceRoot = ctx.cmdLine().modulePath / "src";
        std::error_code ec;
        if (!ctx.cmdLine().modulePath.empty() && fs::is_directory(sourceRoot, ec))
        {
            fs::recursive_directory_iterator       it(sourceRoot, ec);
            const fs::recursive_directory_iterator end;
            while (!ec && it != end)
            {
                if (it->is_regular_file(ec))
                {
                    Utf8 extension = Utf8(it->path().extension().string());
                    extension.make_lower();
                    if (extension == ".md" || extension == ".swg" || extension == ".swgs")
                        paths.push_back(it->path());
                }
                it.increment(ec);
            }

            if (ec)
                return reportDocFileError(ctx, sourceRoot, FileSystem::normalizeSystemMessage(ec));
        }
        else
        {
            for (const SourceFile* file : moduleSourceFiles(ctx.compiler()))
                paths.push_back(file->path());
        }

        std::ranges::sort(paths);
        paths.erase(std::unique(paths.begin(), paths.end()), paths.end());
        return Result::Continue;
    }

    Result generatePages(TaskContext& ctx, PageOptions options, std::vector<fs::path>& outPaths)
    {
        std::vector<fs::path> paths;
        SWC_RESULT(collectPageSourcePaths(ctx, paths));
        SWC_RESULT(appendAdditionalPages(ctx, options, paths));

        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        for (const fs::path& path : paths)
        {
            std::string source;
            SWC_RESULT(readDocumentationSource(ctx, path, source));

            Utf8 content;
            if (path.extension() == ".md")
                content = renderMarkdownLines(renderCtx, splitLines(source));
            else
                content = renderExampleSource(ctx, renderCtx, source);

            fs::path outPath = DocGenerator::outputDirectory(ctx.compiler()) / path.filename();
            outPath.replace_extension(".html");
            outPath = outPath.lexically_normal();

            PageOptions pageOptions  = options;
            pageOptions.titleContent = correctTitle(path.stem().string());
            const Utf8 page          = constructPage(pageOptions, {}, content, true);
            SWC_RESULT(writeDocumentationFile(ctx, outPath, page));
            outPaths.push_back(std::move(outPath));
        }
        return Result::Continue;
    }

    Result generateRuntimeDocumentationOnce(TaskContext& ctx, const fs::path& outputDirectory, uint32_t& outNumFiles)
    {
        PageOptions options = getRuntimePageOptions(ctx.compiler());
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        Utf8 runtimeFileName = "swag.runtime.html";
        fs::path runtimePath  = outputDirectory / fs::path(runtimeFileName.c_str());
        runtimePath           = runtimePath.lexically_normal();
        const Utf8 runtimeKey = Utf8(FileSystem::normalizePath(runtimePath));

        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            if (!g_GeneratedRuntimeDocs.insert(runtimeKey).second)
                return Result::Continue;
        }

        fs::path generatedPath;
        if (generateApi(ctx, options, true, generatedPath) != Result::Continue)
        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            g_GeneratedRuntimeDocs.erase(runtimeKey);
            return Result::Error;
        }
        outNumFiles++;
        return Result::Continue;
    }
}

Result DocGenerator::generate(GenerateResult& outResult) const
{
    SWC_ASSERT(ctx_ != nullptr);
    outResult = {};

    TaskContext&      ctx       = *ctx_;
    CompilerInstance& compiler  = ctx.compiler();
    PageOptions       options   = getPageOptions(compiler);
    const fs::path    outputDir = outputDirectory(compiler);
    if (ctx.cmdLine().outputDoc)
        SWC_RESULT(ensureOutputDirectory(ctx, outputDir));

    if (options.css.empty())
        options.css = "style.css";
    if (options.titleToc.empty())
        options.titleToc = "Table of Contents";
    if (options.titleContent.empty())
    {
        options.titleContent = "Module ";
        options.titleContent += defaultArtifactName(compiler.cmdLine());
    }
    SWC_RESULT(writeDocumentationStyles(ctx, options));

    switch (options.kind)
    {
        case Runtime::BuildCfgDocKind::None:
            break;

        case Runtime::BuildCfgDocKind::Api:
            SWC_RESULT(generateApi(ctx, options, false, outResult.primaryOutput));
            outResult.numFiles++;
            break;

        case Runtime::BuildCfgDocKind::Examples:
            SWC_RESULT(generateExamples(ctx, options, outResult.primaryOutput));
            outResult.numFiles++;
            break;

        case Runtime::BuildCfgDocKind::Pages:
        {
            std::vector<fs::path> paths;
            SWC_RESULT(generatePages(ctx, options, paths));
            outResult.numFiles += static_cast<uint32_t>(paths.size());
            if (!paths.empty())
                outResult.primaryOutput = paths.front();
            break;
        }
    }

    SWC_RESULT(generateRuntimeDocumentationOnce(ctx, outputDir, outResult.numFiles));
    return Result::Continue;
}

fs::path DocGenerator::outputDirectory(const CompilerInstance& compiler)
{
    const CommandLine& cmdLine = compiler.cmdLine();
    if (!cmdLine.docOutputDir.empty())
        return cmdLine.docOutputDir;
    if (!cmdLine.workspacePath.empty())
        return (cmdLine.workspacePath / ".output" / "doc").lexically_normal();
    if (!cmdLine.modulePath.empty())
        return (cmdLine.modulePath / ".output" / "doc").lexically_normal();
    if (!cmdLine.moduleFilePath.empty())
        return (cmdLine.moduleFilePath.parent_path() / ".output" / "doc").lexically_normal();
    return (fs::current_path() / ".output" / "doc").lexically_normal();
}

Utf8 DocGenerator::renderMarkdownForTest(TaskContext& ctx, const std::string_view text)
{
    const PageOptions   options;
    const RenderContext renderCtx = {
        .ctx        = &ctx,
        .options    = &options,
        .references = nullptr,
    };
    return renderMarkdownLines(renderCtx, splitLines(text));
}

SWC_END_NAMESPACE();
