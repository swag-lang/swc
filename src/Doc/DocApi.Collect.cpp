#include "pch.h"
#include "Doc/DocApi.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Utf8 DocApi::displayNameFor(const std::string_view fullName, const DocItemKind kind)
{
    if (kind == DocItemKind::Namespace)
        return fullName;

    const size_t last = fullName.rfind('.');
    if (last == std::string_view::npos)
        return fullName;
    const size_t previous = last ? fullName.rfind('.', last - 1) : std::string_view::npos;
    if (previous == std::string_view::npos)
        return fullName;
    return fullName.substr(previous + 1);
}

namespace
{
    int itemSortOrder(const DocItemKind kind)
    {
        return static_cast<int>(kind);
    }
}

std::optional<DocItemKind> DocApi::itemKind(const Symbol& symbol)
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

bool DocApi::hasNoDocAttribute(const Symbol& symbol)
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

namespace
{
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
        if (!DocApi::itemKind(symbol).has_value() || DocApi::hasNoDocAttribute(symbol))
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
}

bool DocApi::isAnonymousAggregateSymbol(const Symbol& symbol)
{
    const auto* symbolStruct = symbol.safeCast<SymbolStruct>();
    if (!symbolStruct || !symbolStruct->decl())
        return false;

    return symbolStruct->decl()->is(AstNodeId::AnonymousStructDecl) ||
           symbolStruct->decl()->is(AstNodeId::AnonymousUnionDecl);
}

bool DocApi::hasCompilerGeneratedIdentifier(const TaskContext& ctx, const Symbol& symbol)
{
    // Source identifiers cannot use the reserved "__" prefix. Sema uses it for
    // unique anonymous aggregates, lambdas, inline temporaries, and other helpers.
    return symbol.idRef().isValid() && symbol.name(ctx).starts_with("__");
}

// The runtime page is shared by every module, but a runtime symbol is scoped by the module
// that happens to compile it. Dropping that prefix gives one stable anchor per runtime
// symbol, so a link written from any module page reaches it.
Utf8 DocApi::documentationScopedName(TaskContext& ctx, const Symbol& symbol, const bool runtime)
{
    Utf8 result = symbol.getFullScopedName(ctx);
    if (!runtime)
        return result;

    Utf8 prefix = ctx.compiler().buildCfg().moduleNamespace;
    if (prefix.empty())
        return result;
    prefix += ".";
    if (result.starts_with(prefix.view()))
        result.erase(0, prefix.size());
    return result;
}

bool DocApi::isInCompilerGeneratedScope(const TaskContext& ctx, const Symbol& symbol)
{
    // A declaration nested in a reserved scope is implementation state whatever its own
    // spelling, so the whole subtree stays out of the page.
    const Symbol* scan = &symbol;
    while (scan)
    {
        if (hasCompilerGeneratedIdentifier(ctx, *scan))
            return true;
        scan = scan->ownerSymMap();
    }
    return false;
}

namespace
{
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
}

void DocApi::appendNormalizedComment(std::vector<Utf8>& outLines, std::string_view text)
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

    std::vector<Utf8> lines = Utf8Helper::splitLines(text);
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

    while (!outLines.empty() && Utf8Helper::trim(outLines.front()).empty())
        outLines.erase(outLines.begin());
    while (!outLines.empty() && Utf8Helper::trim(outLines.back()).empty())
        outLines.pop_back();
}

namespace
{
    bool collectLeadingCommentTrivia(std::vector<Utf8>& result, const SourceView& srcView, const TokenRef tokenRef)
    {
        if (!tokenRef.isValid() || tokenRef.get() >= srcView.numTokens() || tokenRef.get() + 1 >= srcView.triviaStart().size())
            return false;

        result.clear();
        const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(tokenRef);
        bool hasComment                     = false;
        for (uint32_t i = triviaStart; i < triviaEnd; ++i)
        {
            const SourceTrivia& trivia = srcView.trivia()[i];
            if (trivia.tok.id == TokenId::Whitespace)
            {
                if (Utf8Helper::countLineBreaks(trivia.tok.string(srcView)) >= 2)
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

            DocApi::appendNormalizedComment(result, trivia.tok.string(srcView));
            hasComment = true;
        }

        if (!hasComment)
            result.clear();
        return hasComment;
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

        collectLeadingCommentTrivia(result, srcView, startToken);
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
        const size_t           start  = std::min<size_t>(ModuleApi::Export::sourceTokenByteEnd(srcView, token), source.size());
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

        DocApi::appendNormalizedComment(result, suffix.substr(commentPos));
        return result;
    }
}

std::vector<Utf8> DocApi::symbolCommentLines(TaskContext& ctx, const Symbol& symbol, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef)
{
    std::vector<Utf8> result;
    if (symbol.isConstant() || symbol.isAlias() || symbol.isVariable() || symbol.isEnumValue())
        result = trailingCommentLines(ctx, file, declRef);
    if (result.empty())
        result = leadingCommentLines(ctx, file, rootRef);
    if (result.empty() && declRef != rootRef)
        result = leadingCommentLines(ctx, file, declRef);
    return result;
}

namespace
{
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
        const fs::path  relative = fs::relative(file.path().parent_path(), sourceRoot, ec);
        if (ec || relative.empty() || relative == ".")
            return {};

        std::string value = relative.generic_string();
        if (value.starts_with(".."))
            return {};
        return value;
    }
}

void DocApi::collectSymbolTree(std::vector<const Symbol*>& outSymbols, std::unordered_set<const Symbol*>& seen, const SymbolMap& symbolMap)
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

namespace
{
    const Symbol* documentationImplOwner(const SymbolImpl& impl)
    {
        if (impl.isForStruct())
            return impl.symStruct();
        if (impl.isForEnum())
            return impl.symEnum();
        if (impl.isForInterface())
            return impl.symInterface();
        return nullptr;
    }

    const Symbol* documentationOwner(const Symbol& symbol)
    {
        if (const auto* function = symbol.safeCast<SymbolFunction>())
        {
            if (const SymbolStruct* owner = function->ownerStruct())
                return owner;
        }

        const SymbolMap* owner = symbol.ownerSymMap();
        while (owner)
        {
            if (owner->isStruct() || owner->isInterface() || owner->isEnum())
                return owner;
            if (owner->isImpl())
            {
                if (const Symbol* result = documentationImplOwner(owner->cast<SymbolImpl>()))
                    return result;
            }
            owner = owner->ownerSymMap();
        }
        return nullptr;
    }

    Utf8 documentationNamespace(TaskContext& ctx, const Symbol& symbol, const Symbol* owner, const bool runtime)
    {
        const Symbol*    scopedSymbol = owner ? owner : &symbol;
        const SymbolMap* scope        = scopedSymbol->ownerSymMap();
        while (scope)
        {
            if (scope->isNamespace())
                return DocApi::documentationScopedName(ctx, *scope, runtime);
            scope = scope->ownerSymMap();
        }
        return {};
    }
}

void DocApi::collectDocItems(TaskContext& ctx, std::vector<DocItem>& outItems, const bool runtime)
{
    CompilerInstance&                             compiler = ctx.compiler();
    std::vector<const Symbol*>                    symbols;
    std::unordered_set<const Symbol*>             seen;
    std::unordered_map<const Symbol*, AstNodeRef> publicRootRefs;
    if (runtime)
    {
        if (compiler.symModule())
            collectSymbolTree(symbols, seen, *compiler.symModule());
        if (compiler.importRootNamespace())
            collectSymbolTree(symbols, seen, *compiler.importRootNamespace());
    }
    else
    {
        ModuleApiFileEntries fallbackPublicEntries;
        const ModuleApiFileEntries* publicEntries = compiler.moduleApiPublicEntries();
        if (!publicEntries)
        {
            if (ModuleApi::collectPublicEntries(ctx, fallbackPublicEntries) != Result::Continue)
                return;
            publicEntries = &fallbackPublicEntries;
        }

        for (const ModuleApiFileEntry& fileEntry : *publicEntries | std::views::values)
        {
            for (const ModuleApiPublicEntry& entry : fileEntry.publicEntries)
            {
                if (!entry.symbol || !seen.insert(entry.symbol).second)
                    continue;

                symbols.push_back(entry.symbol);
                publicRootRefs.emplace(entry.symbol, entry.rootRef);

                // Nested types and interface methods are exported through their
                // aggregate root rather than as independent module API entries.
                // Collect the public symbol tree so each of them still receives
                // its own canonical, top-level documentation section.
                if (entry.symbol->isSymMap())
                {
                    std::vector<const Symbol*>        members;
                    std::unordered_set<const Symbol*> nestedSeen;
                    collectSymbolTree(members, nestedSeen, *entry.symbol->asSymMap());
                    for (const Symbol* member : members)
                    {
                        if (!member || !isDocumentationSymbol(compiler, *member, false) || !seen.insert(member).second)
                            continue;
                        symbols.push_back(member);
                    }
                }
            }
        }
    }

    struct DocItemCandidate
    {
        const SourceFile* file = nullptr;
        DocItemKind      kind  = DocItemKind::Function;
        Utf8             fullName;
        Utf8             ownerName;
        Utf8             namespaceName;
        DocOverload      overload;
        bool             valid = false;
    };

    // Sema is complete, so every candidate can be derived independently. The indexed slots
    // keep the subsequent merge in the original symbol order and preserve deterministic HTML.
    std::vector<DocItemCandidate> candidates(symbols.size());
    const auto&                   resolvedPublicRootRefs = publicRootRefs;
    ModuleApi::Export::parallelForIndexed(ctx, static_cast<uint32_t>(symbols.size()), [&](TaskContext& workerCtx, const uint32_t index) {
        const Symbol* symbol = symbols[index];
        if (!symbol || hasNoDocAttribute(*symbol))
            return;
        const std::optional<DocItemKind> kind = itemKind(*symbol);
        if (!kind.has_value())
            return;
        if (runtime && !isDocumentationSymbol(compiler, *symbol, true))
            return;
        if (isAnonymousAggregateSymbol(*symbol) || isInCompilerGeneratedScope(workerCtx, *symbol))
            return;
        if (const auto* function = symbol->safeCast<SymbolFunction>())
        {
            const SymbolImpl* impl = function->declImplContext();
            if (impl && impl->isForInterface())
                return;
        }

        const SourceFile* file = compiler.ownerSourceFile(symbol->srcViewRef());
        if (!file)
            file = compiler.sourceViewFile(*symbol);
        if (!file)
            return;

        AstNodeRef declRef;
        if (!ModuleApi::Internal::tryFindNodeRef(file->ast(), symbol->decl(), declRef))
        {
            if (file->ast().hasSourceView() && symbol->srcViewRef() != file->ast().srcView().ref())
                declRef = file->ast().tryFindNodeRef(symbol->decl());
        }
        if (declRef.isInvalid() || ModuleApi::Internal::isGeneratedSourceDecl(*file, declRef))
            return;

        AstNodeRef rootRef = ModuleApi::Internal::findExportDeclRoot(*file, declRef);
        if (!runtime)
        {
            const auto it = resolvedPublicRootRefs.find(symbol);
            if (it != resolvedPublicRootRefs.end())
                rootRef = it->second;
        }
        if (rootRef.isInvalid())
            return;

        Utf8 fullName = documentationScopedName(workerCtx, *symbol, runtime);
        if (fullName.empty())
            return;

        // A method declared in an 'impl' block is scoped by its type alone, while the
        // same symbol seen from an importing module carries the whole path. Qualifying it
        // here keeps one spelling, so a cross-module link reaches the anchor it names.
        const Symbol* owner = documentationOwner(*symbol);
        Utf8          ownerName;
        if (owner)
        {
            ownerName = documentationScopedName(workerCtx, *owner, runtime);
            if (!ownerName.empty())
            {
                Utf8 qualified = ownerName;
                qualified += ".";
                if (!fullName.starts_with(qualified.view()))
                {
                    const size_t lastPart = fullName.view().rfind('.');
                    qualified.append(lastPart == std::string_view::npos ? fullName.view() : fullName.view().substr(lastPart + 1));
                    fullName = std::move(qualified);
                }
            }
        }

        DocItemCandidate& candidate = candidates[index];
        candidate.file              = file;
        candidate.kind              = *kind;
        candidate.fullName          = std::move(fullName);
        candidate.ownerName         = std::move(ownerName);
        candidate.namespaceName     = documentationNamespace(workerCtx, *symbol, owner, runtime);
        candidate.overload.symbol       = symbol;
        candidate.overload.file         = file;
        candidate.overload.signature    = buildDisplaySignature(workerCtx, *file, declRef, rootRef);
        candidate.overload.commentLines = symbolCommentLines(workerCtx, *symbol, *file, declRef, rootRef);
        candidate.overload.sourceLine   = symbol->codeRange(workerCtx).line + 1;
        candidate.valid                 = true;
    });

    std::unordered_map<Utf8, size_t>            itemIndices;
    std::unordered_set<Utf8>                    overloadKeys;
    std::unordered_map<const SourceFile*, Utf8> sourceCategories;
    for (DocItemCandidate& candidate : candidates)
    {
        if (!candidate.valid)
            continue;

        Utf8 itemKey;
        itemKey.append(std::to_string(itemSortOrder(candidate.kind)));
        itemKey += ":";
        itemKey += candidate.fullName;

        Utf8 overloadKey = itemKey;
        overloadKey += "\n";
        overloadKey += candidate.overload.signature;
        overloadKey += "\n";
        overloadKey.append(candidate.file->path().generic_string());
        overloadKey += ":";
        overloadKey.append(std::to_string(candidate.overload.sourceLine));
        if (!overloadKeys.insert(overloadKey).second)
            continue;

        const auto [it, inserted] = itemIndices.emplace(itemKey, outItems.size());
        if (inserted)
        {
            const auto [categoryIt, categoryInserted] = sourceCategories.try_emplace(candidate.file);
            if (categoryInserted)
                categoryIt->second = sourceCategory(compiler, *candidate.file, runtime);

            DocItem item;
            item.kind          = candidate.kind;
            item.fullName      = candidate.fullName;
            item.displayName   = displayNameFor(candidate.fullName, candidate.kind);
            item.category      = categoryIt->second;
            item.ownerName     = candidate.ownerName;
            item.namespaceName = candidate.namespaceName;
            outItems.push_back(std::move(item));
        }
        outItems[it->second].overloads.push_back(std::move(candidate.overload));
    }

    for (DocItem& item : outItems)
    {
        std::ranges::sort(item.overloads, [](const DocOverload& lhs, const DocOverload& rhs) {
            const std::string lhsPath = lhs.file ? lhs.file->path().generic_string() : std::string{};
            const std::string rhsPath = rhs.file ? rhs.file->path().generic_string() : std::string{};
            if (lhsPath != rhsPath)
                return lhsPath < rhsPath;
            if (lhs.sourceLine != rhs.sourceLine)
                return lhs.sourceLine < rhs.sourceLine;
            return lhs.signature < rhs.signature;
        });
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
SWC_END_NAMESPACE();
