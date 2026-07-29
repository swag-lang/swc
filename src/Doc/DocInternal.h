#pragma once

#include "Backend/Runtime.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

#include <optional>
#include <span>
#include <unordered_map>
#include <unordered_set>
#include <vector>

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class SourceFile;
class Symbol;
class SymbolMap;
class TaskContext;

namespace DocInternal
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
        Utf8                     ownerName;
        Utf8                     namespaceName;
        Utf8                     category;
        std::vector<DocOverload> overloads;
    };

    struct DocGuide
    {
        Utf8              title;
        Utf8              anchor;
        std::vector<Utf8> lines;
    };

    struct DocNamespace
    {
        Utf8                        fullName;
        std::vector<Utf8>           children;
        std::vector<const DocItem*> items;
    };

    using DocItemsByOwner = std::unordered_map<Utf8, std::vector<const DocItem*>>;

    struct RenderContext
    {
        TaskContext*                                      ctx                = nullptr;
        const PageOptions*                                options            = nullptr;
        const std::unordered_map<Utf8, Utf8>*             references         = nullptr;
        const std::unordered_map<Utf8, Utf8>*             externalReferences = nullptr;
        const std::unordered_map<Utf8, Utf8>*             externalModules    = nullptr;
        const std::vector<std::pair<Utf8, Utf8>>*         anonymousTypeNames = nullptr;
        Utf8                                              moduleName;
        Utf8                                              headingAnchorPrefix;
    };

    struct ApiDocument
    {
        std::vector<DocItem>           items;
        std::vector<DocGuide>          guides;
        std::unordered_map<Utf8, Utf8> references;
        std::unordered_map<Utf8, Utf8> externalReferences;
        std::unordered_map<Utf8, Utf8> externalModules;
        Utf8                           toc;
        Utf8                           content;
    };

    Utf8             fromRuntimeString(const Runtime::String& value);
    PageOptions      getPageOptions(const CompilerInstance& compiler);
    PageOptions      getRuntimePageOptions(const CompilerInstance& compiler);
    std::string_view trimView(std::string_view value);
    Utf8             trimCopy(std::string_view value);
    std::vector<Utf8> splitLines(std::string_view text);
    Utf8             escapeHtml(std::string_view text, bool attribute = false);
    Utf8             makeAnchor(std::string_view value);
    Utf8             lastNamePart(std::string_view value);
    Utf8             renderTypeName(const RenderContext& renderCtx, std::string_view typeName);
    Utf8             renderCodeBlock(TaskContext& ctx, std::string_view code, bool swagSyntax, const RenderContext* renderCtx = nullptr);
    Utf8             renderMarkdownLines(const RenderContext& renderCtx, std::span<const Utf8> lines, uint32_t headingOffset = 0);
    std::vector<Utf8> summaryLines(std::span<const Utf8> lines);
    Utf8             codeHtml(TaskContext& ctx, const RenderContext& renderCtx, std::string_view code);
    Utf8             documentationStyles();
    Utf8             constructPage(const PageOptions& options, std::string_view toc, std::string_view content, bool pages);
    Utf8             correctTitle(Utf8 title);
    Result           readDocumentationSource(TaskContext& ctx, const fs::path& path, std::string& outText);
    Result           reportDocFileError(TaskContext& ctx, const fs::path& path, const Utf8& because);
    Result           writeDocumentationFile(TaskContext& ctx, const fs::path& path, std::string_view content);
    fs::path         outputFilePath(const CompilerInstance& compiler, const PageOptions& options);
    Utf8             displayNameFor(std::string_view fullName, DocItemKind kind);
    const char*      itemKindName(DocItemKind kind);
    std::optional<DocItemKind> itemKind(const Symbol& symbol);
    bool             hasNoDocAttribute(const Symbol& symbol);
    bool             isAnonymousAggregateSymbol(const Symbol& symbol);
    bool             hasCompilerGeneratedIdentifier(TaskContext& ctx, const Symbol& symbol);
    void             appendNormalizedComment(std::vector<Utf8>& outLines, std::string_view text);
    std::vector<Utf8> symbolCommentLines(TaskContext& ctx, const Symbol& symbol, const SourceFile& file, AstNodeRef declRef, AstNodeRef rootRef);
    void             collectSymbolTree(std::vector<const Symbol*>& outSymbols, std::unordered_set<const Symbol*>& seen, const SymbolMap& symbolMap);
    void             collectDocItems(TaskContext& ctx, std::vector<DocItem>& outItems, bool runtime);
    void             renderApiDocument(TaskContext& ctx, ApiDocument& document, const PageOptions& options, bool runtime);
    Utf8             defaultModuleDocComment(const CompilerInstance& compiler);
    Result           generateApi(TaskContext& ctx, PageOptions options, bool runtime, fs::path& outPath);
}

SWC_END_NAMESPACE();
