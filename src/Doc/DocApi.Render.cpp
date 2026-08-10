#include "pch.h"
#include "Doc/DocApi.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocMarkdown.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool alphabeticLess(const std::string_view lhs, const std::string_view rhs)
    {
        const size_t size = std::min(lhs.size(), rhs.size());
        for (size_t i = 0; i < size; ++i)
        {
            const int left  = std::tolower(static_cast<unsigned char>(lhs[i]));
            const int right = std::tolower(static_cast<unsigned char>(rhs[i]));
            if (left != right)
                return left < right;
        }
        if (lhs.size() != rhs.size())
            return lhs.size() < rhs.size();
        return lhs < rhs;
    }

    struct DocNamespace
    {
        Utf8                        fullName;
        std::vector<Utf8>           children;
        std::vector<const DocItem*> items;
    };

    using DocItemsByOwner = std::unordered_map<Utf8, std::vector<const DocItem*>>;
    using DocSummaryHtml  = std::unordered_map<const DocItem*, Utf8>;
    using SourcePaths     = std::unordered_map<const SourceFile*, Utf8>;

    Utf8 lastNamePart(const std::string_view value)
    {
        const size_t pos = value.rfind('.');
        if (pos == std::string_view::npos)
            return value;
        return value.substr(pos + 1);
    }

    std::span<const Utf8> summaryLines(const std::span<const Utf8> lines)
    {
        for (size_t index = 0; index < lines.size(); ++index)
        {
            if (Utf8Helper::trim(lines[index]).empty())
                continue;
            return lines.subspan(index, 1);
        }
        return {};
    }

    bool hasDetailedDescription(const std::span<const Utf8> lines)
    {
        bool foundSummary = false;
        for (const Utf8& line : lines)
        {
            if (Utf8Helper::trim(line).empty())
                continue;
            if (foundSummary)
                return true;
            foundSummary = true;
        }
        return false;
    }

    Utf8 codeHtml(const TaskContext& ctx, const DocRenderContext& renderCtx, const std::string_view code)
    {
        if (code.empty())
            return {};
        return DocMarkdown::renderCodeBlock(ctx, code, true, &renderCtx);
    }

    // Drives the accent color of an item card; the displayed kind can carry a space.
    const char* itemKindClass(const DocItemKind kind)
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
                return "alias";
            case DocItemKind::Attribute:
                return "attr";
            case DocItemKind::Function:
                return "func";
        }
        SWC_UNREACHABLE();
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

    // A documentation link may spell a symbol by its short name, so the same spelling can
    // reach several symbols. The candidates are ranked instead of cancelling each other:
    // 'Warning' names the attribute declared in a namespace, not the enum case that happens
    // to repeat the word. Only candidates of equal rank are truly ambiguous, and those stay
    // unresolved so the page shows the link is imprecise.
    enum class ReferenceRank : uint8_t
    {
        QualifiedName,
        OwnerQualifiedName,
        TopLevelName,
        OwnedName,
        MemberName,
    };

    struct ReferenceTable
    {
        std::unordered_map<Utf8, Utf8>          entries;
        std::unordered_map<Utf8, ReferenceRank> ranks;
        std::unordered_set<Utf8>                ambiguous;
    };

    void addReference(ReferenceTable& table, const Utf8& name, const Utf8& anchor, const ReferenceRank rank)
    {
        if (name.empty())
            return;

        const auto rankIt = table.ranks.find(name);
        if (rankIt != table.ranks.end())
        {
            if (rank > rankIt->second)
                return;
            if (rank == rankIt->second)
            {
                if (table.entries[name] == anchor)
                    return;
                table.entries.erase(name);
                table.ambiguous.insert(name);
                return;
            }
            table.ambiguous.erase(name);
        }

        table.entries[name] = anchor;
        table.ranks[name]   = rank;
    }

    void buildReferences(const DocApiDocument& document, ReferenceTable& table)
    {
        for (const DocItem& item : document.items)
        {
            const Utf8          anchor    = DocMarkdown::makeAnchor(item.fullName);
            const ReferenceRank shortRank = item.ownerName.empty() ? ReferenceRank::TopLevelName : ReferenceRank::OwnedName;
            addReference(table, item.fullName, anchor, ReferenceRank::QualifiedName);
            addReference(table, item.displayName, anchor, ReferenceRank::OwnerQualifiedName);
            addReference(table, lastNamePart(item.fullName), anchor, shortRank);
        }
    }

    Utf8 externalModulePage(const DocPageOptions& options, Utf8 moduleName)
    {
        Utf8         prefix;
        const size_t separator = options.outputName.rfind('.');
        if (separator != Utf8::npos)
            prefix = options.outputName.subView(0, separator + 1);
        moduleName.make_lower();
        prefix += moduleName;
        prefix += ".html";
        return prefix;
    }

    void buildExternalReferences(TaskContext& ctx, DocApiDocument& document, ReferenceTable& table, const DocPageOptions& options)
    {
        const SymbolMap* imports = ctx.compiler().importRootNamespace();
        if (!imports)
            return;

        std::vector<const Symbol*> importedModules;
        imports->getAllSymbols(importedModules);
        for (const Symbol* importedModule : importedModules)
        {
            if (!importedModule)
                continue;

            Utf8         moduleName = importedModule->getFullScopedName(ctx);
            const size_t separator  = moduleName.find('.');
            if (separator != Utf8::npos)
                moduleName = moduleName.subView(0, separator);
            if (moduleName.empty())
                continue;

            const Utf8 page = moduleName == "Swag" ? Utf8("swag.runtime.html") : externalModulePage(options, moduleName);
            document.externalModules.emplace(moduleName, page);

            if (!importedModule->isSymMap())
                continue;

            std::vector<const Symbol*>        symbols;
            std::unordered_set<const Symbol*> seen;
            DocApi::collectSymbolTree(symbols, seen, *importedModule->asSymMap());
            for (const Symbol* symbol : symbols)
            {
                if (!symbol || !DocApi::itemKind(*symbol).has_value() || DocApi::isAnonymousAggregateSymbol(*symbol) || DocApi::isInCompilerGeneratedScope(ctx, *symbol))
                    continue;

                const Utf8 fullName = symbol->getFullScopedName(ctx);
                if (fullName.empty())
                    continue;
                Utf8 href = page;
                href += "#";
                if (symbol->isNamespace())
                    href += "namespace_";
                href += DocMarkdown::makeAnchor(fullName);
                addReference(table, fullName, href, ReferenceRank::QualifiedName);
                addReference(table, DocApi::displayNameFor(fullName, *DocApi::itemKind(*symbol)), href, ReferenceRank::OwnerQualifiedName);
                addReference(table, lastNamePart(fullName), href, symbol->ownerSymMap() && !symbol->ownerSymMap()->isNamespace() ? ReferenceRank::OwnedName : ReferenceRank::TopLevelName);
            }
        }
    }

    Utf8 buildSourcePath(const CompilerInstance& compiler, const SourceFile& file, const bool runtime)
    {
        fs::path relative = file.path().filename();
        if (!runtime && !compiler.cmdLine().modulePath.empty())
        {
            std::error_code ec;
            const fs::path  candidate = fs::relative(file.path(), compiler.cmdLine().modulePath, ec);
            if (!ec && !candidate.empty() && !candidate.generic_string().starts_with(".."))
                relative = candidate;
        }
        return relative.generic_string();
    }

    void buildSourcePaths(SourcePaths& outPaths, const CompilerInstance& compiler, const DocApiDocument& document, const bool runtime)
    {
        for (const DocItem& item : document.items)
        {
            if (item.overloads.empty())
                continue;
            const DocOverload& overload = item.overloads.front();
            if (overload.file && !outPaths.contains(overload.file))
                outPaths.emplace(overload.file, buildSourcePath(compiler, *overload.file, runtime));
        }
    }

    Utf8 sourceLink(const CompilerInstance& compiler, const SourcePaths& sourcePaths, const DocOverload& overload, const bool runtime)
    {
        Utf8 repoPath = compiler.buildCfg().repoPath;
        if (runtime)
            repoPath = "https://github.com/swag-lang/swc/blob/master/bin/runtime";
        if (repoPath.empty() || !overload.file)
            return {};

        const auto pathIt = sourcePaths.find(overload.file);
        SWC_ASSERT(pathIt != sourcePaths.end());

        Utf8 result = repoPath;
        if (!result.empty() && result.back() != '/')
            result += "/";
        result += pathIt->second;
        result.append(std::format("#L{}", overload.sourceLine));
        return result;
    }

    void buildMemberReferences(const DocApiDocument& document, ReferenceTable& table)
    {
        for (const DocItem& item : document.items)
        {
            for (const DocMember& member : item.members)
            {
                if (member.fullName.empty())
                    continue;
                const Utf8 anchor = DocMarkdown::makeAnchor(member.fullName);
                addReference(table, member.fullName, anchor, ReferenceRank::QualifiedName);
                addReference(table, DocApi::displayNameFor(member.fullName, DocItemKind::Function), anchor, ReferenceRank::OwnerQualifiedName);
                addReference(table, member.name, anchor, ReferenceRank::MemberName);
            }
        }
    }

    void buildDocNamespaces(const DocApiDocument& document, std::vector<DocNamespace>& namespaces, ReferenceTable& table)
    {
        std::unordered_set<Utf8> names;
        for (const DocItem& item : document.items)
        {
            Utf8 name = item.namespaceName;
            while (!name.empty())
            {
                names.insert(name);
                const size_t separator = name.rfind('.');
                if (separator == Utf8::npos)
                    break;
                name = name.subView(0, separator);
            }
        }

        std::vector sortedNames(names.begin(), names.end());
        std::ranges::sort(sortedNames, alphabeticLess);
        std::unordered_map<Utf8, size_t> indices;
        for (Utf8& name : sortedNames)
        {
            indices.emplace(name, namespaces.size());
            namespaces.push_back({.fullName = std::move(name)});
        }

        for (DocNamespace& docNamespace : namespaces)
        {
            const size_t separator = docNamespace.fullName.rfind('.');
            if (separator != Utf8::npos)
            {
                const Utf8 parent   = docNamespace.fullName.subView(0, separator);
                const auto parentIt = indices.find(parent);
                if (parentIt != indices.end())
                    namespaces[parentIt->second].children.push_back(docNamespace.fullName);
            }
        }

        for (const DocItem& item : document.items)
        {
            if (!item.ownerName.empty() || item.kind == DocItemKind::Namespace)
                continue;
            const auto it = indices.find(item.namespaceName);
            if (it != indices.end())
                namespaces[it->second].items.push_back(&item);
        }

        for (const DocNamespace& docNamespace : namespaces)
        {
            const Utf8 anchor = std::format("namespace_{}", DocMarkdown::makeAnchor(docNamespace.fullName));
            addReference(table, docNamespace.fullName, anchor, ReferenceRank::QualifiedName);
            addReference(table, lastNamePart(docNamespace.fullName), anchor, ReferenceRank::TopLevelName);
        }
    }

    void collectAnonymousTypeNames(TaskContext& ctx, std::vector<std::pair<Utf8, Utf8>>& outNames, std::unordered_set<uint32_t>& seen, const TypeRef typeRef)
    {
        if (!typeRef.isValid() || !seen.insert(typeRef.get()).second)
            return;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isStruct())
        {
            const SymbolStruct& symbolStruct = type.payloadSymStruct();
            const SymbolStruct* root         = symbolStruct.genericRootOrSelf();
            if (root && (DocApi::isAnonymousAggregateSymbol(*root) || DocApi::hasCompilerGeneratedIdentifier(ctx, *root)))
            {
                const Utf8 fullName    = root->getFullScopedName(ctx);
                const Utf8 replacement = root->isUnion() ? "union { ... }" : "struct { ... }";
                if (!fullName.empty())
                    outNames.emplace_back(fullName, replacement);
            }

            SmallVector<GenericInstanceKey> args;
            if (symbolStruct.tryGetGenericInstanceArgs(args))
            {
                for (const GenericInstanceKey& arg : args)
                {
                    collectAnonymousTypeNames(ctx, outNames, seen, arg.typeRef);
                    if (arg.cstRef.isValid())
                    {
                        const ConstantValue& constant = ctx.cstMgr().get(arg.cstRef);
                        if (constant.isTypeValue())
                            collectAnonymousTypeNames(ctx, outNames, seen, constant.getTypeValue());
                    }
                }
            }
            return;
        }

        if (type.isAlias())
        {
            collectAnonymousTypeNames(ctx, outNames, seen, type.payloadSymAlias().underlyingTypeRef());
            return;
        }

        if (type.isArray())
        {
            collectAnonymousTypeNames(ctx, outNames, seen, type.payloadArrayElemTypeRef());
            for (const TypeRef indexTypeRef : type.payloadArrayIndexTypeRefs())
                collectAnonymousTypeNames(ctx, outNames, seen, indexTypeRef);
            return;
        }

        if (type.isSlice() || type.isAnyPointer() || type.isReference() || type.isTypeValue() || type.isTypedVariadic() || type.isCodeBlock())
        {
            collectAnonymousTypeNames(ctx, outNames, seen, type.payloadTypeRef());
            return;
        }

        if (type.isFunction())
        {
            const SymbolFunction& function = type.payloadSymFunction();
            collectAnonymousTypeNames(ctx, outNames, seen, function.returnTypeRef());
            for (const SymbolVariable* parameter : function.parameters())
            {
                if (parameter)
                    collectAnonymousTypeNames(ctx, outNames, seen, parameter->typeRef());
            }
            return;
        }

        if (type.isAggregate())
        {
            for (const TypeRef childTypeRef : type.payloadAggregate().types)
                collectAnonymousTypeNames(ctx, outNames, seen, childTypeRef);
        }
    }

    Utf8 documentationTypeName(const DocRenderContext& renderCtx, const Symbol& symbol)
    {
        if (!symbol.typeRef().isValid())
            return {};

        TaskContext&                       ctx    = *renderCtx.ctx;
        Utf8                               result = symbol.typeInfo(ctx).toFullName(ctx);
        std::vector<std::pair<Utf8, Utf8>> anonymousNames;
        std::unordered_set<uint32_t>       seen;
        collectAnonymousTypeNames(ctx, anonymousNames, seen, symbol.typeRef());
        for (const auto& [name, replacement] : anonymousNames)
            result.replace_loop(name, replacement);
        if (renderCtx.anonymousTypeNames)
        {
            for (const auto& [name, replacement] : *renderCtx.anonymousTypeNames)
                result.replace_loop(name, replacement);
        }

        // Generic constant arguments can preserve a cloned anonymous type name after
        // sema has detached the clone from its source declaration. The "__" prefix is
        // reserved to the compiler, so remove the whole qualified token as a final
        // boundary guarantee instead of exposing implementation-generated spelling.
        size_t generatedPos = result.find("__");
        while (generatedPos != Utf8::npos)
        {
            size_t start = generatedPos;
            while (start)
            {
                const char c = result[start - 1];
                if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '.')
                    break;
                start--;
            }

            size_t end = generatedPos + 2;
            while (end < result.size())
            {
                const char c = result[end];
                if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_')
                    break;
                end++;
            }

            result.replace(start, end - start, "anonymous aggregate");
            generatedPos = result.find("__", start);
        }
        return result;
    }

    void renderMemberTable(Utf8& content, const DocRenderContext& renderCtx, const DocItem& item)
    {
        if (item.members.empty())
            return;

        const bool isEnum = item.kind == DocItemKind::Enum;
        content.append(std::format("<h3>{}</h3>\n<table class=\"table-enumeration api-summary\">\n<thead><tr><th>Name</th>", isEnum ? "Cases" : "Fields"));
        if (!isEnum)
            content += "<th>Type</th>";
        content += "<th>Description</th></tr></thead>\n<tbody>\n";
        bool hasDetails = false;
        for (const DocMember& member : item.members)
        {
            const Utf8 anchor  = DocMarkdown::makeAnchor(member.fullName);
            const bool details = hasDetailedDescription(member.commentLines);
            hasDetails |= details;
            if (details)
                content.append(std::format(R"(<tr><td class="code-type"><a href="#{}">{}</a></td>)", anchor, Utf8Helper::escapeHtml(member.name)));
            else
                content.append(std::format(R"(<tr><td id="{}" class="code-type">{}</td>)", anchor, Utf8Helper::escapeHtml(member.name)));
            if (!isEnum)
            {
                Utf8 typeNameHtml;
                if (member.typeName.empty() && member.symbol)
                    typeNameHtml = DocMarkdown::renderTypeName(renderCtx, documentationTypeName(renderCtx, *member.symbol));
                else
                    typeNameHtml = Utf8Helper::escapeHtml(member.typeName);
                content.append(std::format("<td class=\"code-type\">{}</td>", typeNameHtml));
            }
            const std::span<const Utf8> summary = summaryLines(member.commentLines);
            content.append(std::format("<td>{}</td></tr>\n", DocMarkdown::renderLines(renderCtx, summary)));
        }
        content += "</tbody>\n</table>\n";

        if (!hasDetails)
            return;

        const Utf8 ownerAnchor = DocMarkdown::makeAnchor(item.fullName);
        content.append(std::format("<h3 id=\"{}_member-details\">{} details</h3>\n<div class=\"api-member-details\">\n", ownerAnchor, isEnum ? "Case" : "Field"));
        for (const DocMember& member : item.members)
        {
            if (!hasDetailedDescription(member.commentLines))
                continue;
            const Utf8 anchor = DocMarkdown::makeAnchor(member.fullName);
            content.append(std::format(R"(<section class="api-member-detail"><h4 id="{}"><span class="api-member-name">{}</span><a class="api-member-permalink" href="#{}" aria-label="Permalink">#</a></h4>)", anchor, Utf8Helper::escapeHtml(member.name), anchor));
            content += "\n";
            DocRenderContext memberRenderCtx    = renderCtx;
            memberRenderCtx.headingAnchorPrefix = anchor;
            content += DocMarkdown::renderLines(memberRenderCtx, member.commentLines);
            content += "</section>\n";
        }
        content += "</div>\n";
    }

    void renderSummaryTable(Utf8& content, const DocSummaryHtml& summaryHtml, const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items, const bool showKind, const bool shortNames)
    {
        if (items.empty())
            return;

        content.append(std::format("<h3 id=\"{}\">{}</h3>\n<table class=\"api-summary\">\n<thead><tr><th>Name</th>", anchor, Utf8Helper::escapeHtml(title)));
        if (showKind)
            content += "<th>Kind</th>";
        content += "<th>Description</th></tr></thead>\n<tbody>\n";
        for (const DocItem* item : items)
        {
            if (!item || item->overloads.empty())
                continue;
            const Utf8 name = shortNames ? lastNamePart(item->fullName) : item->displayName;
            content.append(std::format(R"(<tr><td class="code-type"><a href="#{}">{}</a></td>)", DocMarkdown::makeAnchor(item->fullName), Utf8Helper::escapeHtml(name)));
            if (showKind)
                content.append(std::format(R"(<td><span class="kind-chip kind-{}">{}</span></td>)", itemKindClass(item->kind), itemKindName(item->kind)));
            const auto summaryIt = summaryHtml.find(item);
            content.append(std::format("<td>{}</td></tr>\n", summaryIt == summaryHtml.end() ? std::string_view{} : summaryIt->second.view()));
        }
        content += "</tbody>\n</table>\n";
    }

    void renderNamespaceTable(Utf8& content, const std::string_view title, const std::string_view anchor, std::span<const Utf8> namespaces)
    {
        if (namespaces.empty())
            return;
        content.append(std::format("<h3 id=\"{}\">{}</h3>\n<table class=\"api-summary\">\n<thead><tr><th>Namespace</th></tr></thead>\n<tbody>\n", anchor, Utf8Helper::escapeHtml(title)));
        for (const Utf8& name : namespaces)
            content.append(std::format("<tr><td class=\"code-type\"><a href=\"#namespace_{}\">{}</a></td></tr>\n", DocMarkdown::makeAnchor(name), Utf8Helper::escapeHtml(name)));
        content += "</tbody>\n</table>\n";
    }

    // The four summary tables a namespace or an owner publishes, in the order they are rendered.
    struct DocItemBuckets
    {
        std::vector<const DocItem*> types;
        std::vector<const DocItem*> enumerations;
        std::vector<const DocItem*> constants;
        std::vector<const DocItem*> functions;
    };

    bool docItemNameLess(const DocItem* lhs, const DocItem* rhs)
    {
        SWC_ASSERT(lhs != nullptr && rhs != nullptr);
        if (lhs->displayName != rhs->displayName)
            return alphabeticLess(lhs->displayName, rhs->displayName);
        return alphabeticLess(lhs->fullName, rhs->fullName);
    }

    void sortDocItems(std::vector<const DocItem*>& items)
    {
        std::ranges::sort(items, docItemNameLess);
    }

    DocItemBuckets bucketDocItems(const std::vector<const DocItem*>& items)
    {
        DocItemBuckets buckets;
        for (const DocItem* item : items)
        {
            switch (item->kind)
            {
                case DocItemKind::Struct:
                case DocItemKind::Interface:
                case DocItemKind::Alias:
                    buckets.types.push_back(item);
                    break;
                case DocItemKind::Enum:
                    buckets.enumerations.push_back(item);
                    break;
                case DocItemKind::Constant:
                    buckets.constants.push_back(item);
                    break;
                case DocItemKind::Function:
                case DocItemKind::Attribute:
                    buckets.functions.push_back(item);
                    break;
                case DocItemKind::Namespace:
                    break;
            }
        }

        sortDocItems(buckets.types);
        sortDocItems(buckets.enumerations);
        sortDocItems(buckets.constants);
        sortDocItems(buckets.functions);

        return buckets;
    }

    void renderNamespaceItem(Utf8& content, const DocSummaryHtml& summaryHtml, const DocNamespace& docNamespace)
    {
        const Utf8 anchor = std::format("namespace_{}", DocMarkdown::makeAnchor(docNamespace.fullName));
        content += "<section class=\"api-symbol\">\n<div class=\"api-item api-item-namespace\">";
        content.append(std::format(R"(<span id="{}" class="api-item-title"><span class="api-item-title-kind">namespace</span> <span class="api-item-title-strong">{}</span> <a class="api-item-permalink" href="#{}" aria-label="Permalink">#</a></span>)", anchor, Utf8Helper::escapeHtml(docNamespace.fullName), anchor));
        content += "</div>\n";
        content.append(std::format("<p>Public API declared directly in <span class=\"code-inline\">{}</span>.</p>\n", Utf8Helper::escapeHtml(docNamespace.fullName)));

        const DocItemBuckets buckets = bucketDocItems(docNamespace.items);

        renderNamespaceTable(content, "Namespaces", std::format("{}_namespaces", anchor), docNamespace.children);
        renderSummaryTable(content, summaryHtml, "Types", std::format("{}_types", anchor), buckets.types, true, false);
        renderSummaryTable(content, summaryHtml, "Enumerations", std::format("{}_enumerations", anchor), buckets.enumerations, false, false);
        renderSummaryTable(content, summaryHtml, "Constants", std::format("{}_constants", anchor), buckets.constants, false, false);
        renderSummaryTable(content, summaryHtml, "Functions", std::format("{}_functions", anchor), buckets.functions, false, false);
        content += "</section>\n";
    }

    void renderOwnedSymbolTables(Utf8& content, const DocSummaryHtml& summaryHtml, const Utf8& ownerName, const DocItemsByOwner& itemsByOwner)
    {
        const auto ownerIt = itemsByOwner.find(ownerName);
        if (ownerIt == itemsByOwner.end())
            return;

        const DocItemBuckets buckets = bucketDocItems(ownerIt->second);

        const Utf8 anchor = DocMarkdown::makeAnchor(ownerName);
        renderSummaryTable(content, summaryHtml, "Nested types", std::format("{}_types", anchor), buckets.types, true, true);
        renderSummaryTable(content, summaryHtml, "Enumerations", std::format("{}_enumerations", anchor), buckets.enumerations, false, true);
        renderSummaryTable(content, summaryHtml, "Constants", std::format("{}_constants", anchor), buckets.constants, false, true);
        renderSummaryTable(content, summaryHtml, "Methods", std::format("{}_methods", anchor), buckets.functions, false, true);
    }

    void renderDocItem(Utf8& content, DocRenderContext& renderCtx, const SourcePaths& sourcePaths, const DocItem& item, const bool runtime)
    {
        if (item.overloads.empty())
            return;

        const DocOverload& first  = item.overloads.front();
        const Utf8         link   = sourceLink(renderCtx.ctx->compiler(), sourcePaths, first, runtime);
        const Utf8         anchor = DocMarkdown::makeAnchor(item.fullName);

        content += "<section class=\"api-symbol\">\n";
        content.append(std::format("<div class=\"api-item api-item-{}\">", itemKindClass(item.kind)));
        content.append(std::format(R"(<span id="{}" class="api-item-title"><span class="api-item-title-kind">{}</span> <span class="api-item-title-strong">{}</span> <a class="api-item-permalink" href="#{}" aria-label="Permalink">#</a></span>)", anchor, itemKindName(item.kind), Utf8Helper::escapeHtml(item.displayName), anchor));
        if (!link.empty())
            content.append(std::format(R"(<a class="api-item-title-src-ref" href="{}">src</a>)", Utf8Helper::escapeHtml(link, true)));
        content += "</div>\n";

        for (size_t overloadIndex = 0; overloadIndex < item.overloads.size(); ++overloadIndex)
        {
            const DocOverload& overload   = item.overloads[overloadIndex];
            renderCtx.headingAnchorPrefix = std::format("{}_{}", DocMarkdown::makeAnchor(item.fullName), overloadIndex);
            if (!overload.commentLines.empty())
                content += DocMarkdown::renderLines(renderCtx, overload.commentLines);
            if (!overload.signature.empty() && item.kind != DocItemKind::Namespace)
                content += codeHtml(*renderCtx.ctx, renderCtx, overload.signature);
        }
        content += "</section>\n";
    }
}

void DocApi::renderApiDocument(TaskContext& ctx, DocApiDocument& document, const DocPageOptions& options, const bool runtime)
{
    document.toc.reserve(document.items.size() * 96 + document.guides.size() * 96 + 512);
    document.content.reserve(document.items.size() * 1024 + document.guides.size() * 4096 + 4096);

    ReferenceTable references;
    buildReferences(document, references);
    buildMemberReferences(document, references);
    std::vector<DocNamespace> namespaces;
    buildDocNamespaces(document, namespaces, references);
    document.references = std::move(references.entries);

    std::vector<const Symbol*>        symbols;
    std::unordered_set<const Symbol*> seenSymbols;
    if (ctx.compiler().symModule())
        collectSymbolTree(symbols, seenSymbols, *ctx.compiler().symModule());
    if (ctx.compiler().importRootNamespace())
        collectSymbolTree(symbols, seenSymbols, *ctx.compiler().importRootNamespace());
    ReferenceTable externalReferences;
    buildExternalReferences(ctx, document, externalReferences, options);
    document.externalReferences = std::move(externalReferences.entries);

    std::vector<std::pair<Utf8, Utf8>> anonymousTypeNames;
    std::unordered_set<Utf8>           seenNames;
    for (const Symbol* symbol : symbols)
    {
        const auto* symbolStruct = symbol ? symbol->safeCast<SymbolStruct>() : nullptr;
        if (!symbolStruct || (!isAnonymousAggregateSymbol(*symbolStruct) && !hasCompilerGeneratedIdentifier(ctx, *symbolStruct)))
            continue;

        const Utf8 fullName = symbolStruct->getFullScopedName(ctx);
        if (fullName.empty() || !seenNames.insert(fullName).second)
            continue;
        anonymousTypeNames.emplace_back(fullName, symbolStruct->isUnion() ? "union { ... }" : "struct { ... }");
    }

    Utf8 moduleName = ctx.compiler().buildCfg().moduleNamespace;
    if (moduleName.empty())
        moduleName = options.titleContent;

    DocRenderContext renderCtx = {
        .ctx                = &ctx,
        .options            = &options,
        .references         = &document.references,
        .externalReferences = &document.externalReferences,
        .externalModules    = &document.externalModules,
        .anonymousTypeNames = &anonymousTypeNames,
        .moduleName         = moduleName,
    };
    SourcePaths sourcePaths;
    buildSourcePaths(sourcePaths, ctx.compiler(), document, runtime);

    DocSummaryHtml summaryHtml;
    summaryHtml.reserve(document.items.size());
    for (const DocItem& item : document.items)
    {
        if (item.overloads.empty())
            continue;
        const std::span<const Utf8> summary = summaryLines(item.overloads.front().commentLines);
        summaryHtml.emplace(&item, DocMarkdown::renderLines(renderCtx, summary));
    }

    document.toc += "<h3>Start here</h3>\n<ul>\n<li><a href=\"#overview\">Overview</a></li>\n";
    for (const DocGuide& guide : document.guides)
        document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", guide.anchor, Utf8Helper::escapeHtml(guide.title)));
    document.toc += "</ul>\n<h3>API reference</h3>\n<ul>\n<li><a href=\"#api-reference\">At a glance</a></li>\n<li><a href=\"#detailed-reference\">Detailed reference</a></li>\n</ul>\n";

    std::vector<const DocItem*> types;
    std::vector<const DocItem*> enumerations;
    std::vector<const DocItem*> constants;
    std::vector<const DocItem*> functions;
    std::vector<const DocItem*> other;
    DocItemsByOwner             itemsByOwner;
    for (const DocItem& item : document.items)
    {
        if (!item.ownerName.empty())
            itemsByOwner[item.ownerName].push_back(&item);

        switch (item.kind)
        {
            case DocItemKind::Struct:
            case DocItemKind::Interface:
            case DocItemKind::Alias:
                types.push_back(&item);
                break;
            case DocItemKind::Enum:
                enumerations.push_back(&item);
                break;
            case DocItemKind::Constant:
                constants.push_back(&item);
                break;
            case DocItemKind::Function:
            case DocItemKind::Attribute:
                functions.push_back(&item);
                break;
            case DocItemKind::Namespace:
                other.push_back(&item);
                break;
        }
    }

    sortDocItems(types);
    sortDocItems(enumerations);
    sortDocItems(constants);
    sortDocItems(functions);
    sortDocItems(other);

    // A long list stays folded so the rail keeps showing every group at once; a short one
    // is more useful open, because it then works as the complete map of the module.
    constexpr size_t tocOpenLimit = 24;

    const auto appendTocGroup = [&](const std::string_view title, const std::string_view anchor, const size_t count, const auto& appendEntries) {
        if (!count)
            return;
        if (!options.hasSymbolIndex)
        {
            document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", anchor, Utf8Helper::escapeHtml(title)));
            return;
        }
        document.toc.append(std::format("<details class=\"toc-group\"{}>\n<summary>{}<span class=\"toc-count\">{}</span></summary>\n<ul class=\"toc-symbols\">\n<li><a href=\"#{}\">All {}</a></li>\n", count <= tocOpenLimit ? " open" : "", Utf8Helper::escapeHtml(title), count, anchor, Utf8Helper::escapeHtml(title)));
        appendEntries();
        document.toc += "</ul>\n</details>\n";
    };

    if (!options.hasSymbolIndex)
        document.toc += "<ul>\n";
    appendTocGroup("Namespaces", "summary-namespaces", namespaces.size(), [&] {
        for (const DocNamespace& docNamespace : namespaces)
            document.toc.append(std::format("<li><a href=\"#namespace_{}\">{}</a></li>\n", DocMarkdown::makeAnchor(docNamespace.fullName), Utf8Helper::escapeHtml(docNamespace.fullName)));
    });

    const auto appendTocSymbols = [&](const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items) {
        appendTocGroup(title, anchor, items.size(), [&] {
            for (const DocItem* item : items)
                document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", DocMarkdown::makeAnchor(item->fullName), Utf8Helper::escapeHtml(item->displayName)));
        });
    };
    appendTocSymbols("Types", "summary-types", types);
    appendTocSymbols("Enumerations", "summary-enumerations", enumerations);
    appendTocSymbols("Constants", "summary-constants", constants);
    appendTocSymbols("Functions", "summary-functions", functions);
    if (!options.hasSymbolIndex)
        document.toc += "</ul>\n";

    for (const DocGuide& guide : document.guides)
    {
        renderCtx.headingAnchorPrefix = guide.anchor;
        document.content.append(std::format("<section class=\"api-guide\"><h2 id=\"{}\">{}</h2>\n", guide.anchor, Utf8Helper::escapeHtml(guide.title)));
        document.content += DocMarkdown::renderLines(renderCtx, guide.lines, 1);
        document.content += "</section>\n";
    }

    document.content += "<section class=\"api-overview\">\n<h2 id=\"api-reference\">API reference</h2>\n<p>Use these summaries to find the right entry point. Every linked symbol also has one standalone, fully qualified reference entry below.</p>\n";
    document.namespaceNames.reserve(namespaces.size());
    for (const DocNamespace& docNamespace : namespaces)
        document.namespaceNames.push_back(docNamespace.fullName);
    renderNamespaceTable(document.content, "Namespaces", "summary-namespaces", document.namespaceNames);
    renderSummaryTable(document.content, summaryHtml, "Types", "summary-types", types, true, false);
    renderSummaryTable(document.content, summaryHtml, "Enumerations", "summary-enumerations", enumerations, false, false);
    renderSummaryTable(document.content, summaryHtml, "Constants", "summary-constants", constants, false, false);
    renderSummaryTable(document.content, summaryHtml, "Functions", "summary-functions", functions, false, false);
    document.content += "</section>\n<h2 id=\"detailed-reference\">Detailed reference</h2>\n";

    const auto renderGroup = [&](const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items) {
        if (items.empty())
            return;
        document.content.append(std::format("<h3 id=\"{}\">{}</h3>\n", anchor, Utf8Helper::escapeHtml(title)));
        for (const DocItem* item : items)
        {
            renderDocItem(document.content, renderCtx, sourcePaths, *item, runtime);
            renderMemberTable(document.content, renderCtx, *item);
            renderOwnedSymbolTables(document.content, summaryHtml, item->fullName, itemsByOwner);
        }
    };

    if (!namespaces.empty())
    {
        document.content += "<h3 id=\"namespaces\">Namespaces</h3>\n";
        for (const DocNamespace& docNamespace : namespaces)
            renderNamespaceItem(document.content, summaryHtml, docNamespace);
    }
    renderGroup("Types", "types", types);
    renderGroup("Enumerations", "enumerations", enumerations);
    renderGroup("Constants", "constants", constants);
    renderGroup("Functions", "functions", functions);
    renderGroup("Other symbols", "other-symbols", other);
}
SWC_END_NAMESPACE();
