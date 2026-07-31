#pragma once

#include "Doc/DocTypes.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

#include <optional>
#include <unordered_set>

SWC_BEGIN_NAMESPACE();

class SourceFile;
class Symbol;
class SymbolMap;
class TaskContext;

class DocApi
{
public:
    static Utf8                       displayNameFor(std::string_view fullName, DocItemKind kind);
    static std::optional<DocItemKind> itemKind(const Symbol& symbol);
    static bool                       hasNoDocAttribute(const Symbol& symbol);
    static bool                       isAnonymousAggregateSymbol(const Symbol& symbol);
    static bool                       hasCompilerGeneratedIdentifier(const TaskContext& ctx, const Symbol& symbol);
    static bool                       isInCompilerGeneratedScope(const TaskContext& ctx, const Symbol& symbol);
    static Utf8                       documentationScopedName(TaskContext& ctx, const Symbol& symbol, bool runtime);
    static void                       appendNormalizedComment(std::vector<Utf8>& outLines, std::string_view text);
    static std::vector<Utf8>          symbolCommentLines(TaskContext& ctx, const Symbol& symbol, const SourceFile& file, AstNodeRef declRef, AstNodeRef rootRef);
    static void                       collectSymbolTree(std::vector<const Symbol*>& outSymbols, std::unordered_set<const Symbol*>& seen, const SymbolMap& symbolMap);
    static void                       collectDocItems(TaskContext& ctx, std::vector<DocItem>& outItems, bool runtime);
    static void                       renderApiDocument(TaskContext& ctx, DocApiDocument& document, const DocPageOptions& options, bool runtime);
    static Result                     generate(TaskContext& ctx, DocPageOptions options, bool runtime, fs::path& outPath);
};

SWC_END_NAMESPACE();
