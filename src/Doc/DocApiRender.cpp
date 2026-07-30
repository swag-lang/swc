#include "pch.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocInternal.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace DocInternal
{

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

    Utf8 externalModulePage(const PageOptions& options, Utf8 moduleName)
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

    void buildExternalReferences(TaskContext& ctx, ApiDocument& document, const PageOptions& options)
    {
        const SymbolMap* imports = ctx.compiler().importRootNamespace();
        if (!imports)
            return;

        std::vector<const Symbol*> importedModules;
        imports->getAllSymbols(importedModules);
        std::unordered_set<Utf8> ambiguous;
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
            collectSymbolTree(symbols, seen, *importedModule->asSymMap());
            for (const Symbol* symbol : symbols)
            {
                if (!symbol || !itemKind(*symbol).has_value() || isAnonymousAggregateSymbol(*symbol) || hasCompilerGeneratedIdentifier(ctx, *symbol))
                    continue;

                const Utf8 fullName = symbol->getFullScopedName(ctx);
                if (fullName.empty())
                    continue;
                Utf8 href = page;
                href += "#";
                if (symbol->isNamespace())
                    href += "namespace_";
                href += makeAnchor(fullName);
                addReference(document.externalReferences, ambiguous, fullName, href);
                addReference(document.externalReferences, ambiguous, lastNamePart(fullName), href);
                addReference(document.externalReferences, ambiguous, displayNameFor(fullName, *itemKind(*symbol)), href);
            }
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
        return ModuleApi::isCurrentModuleSourceFile(*file) && (symbol.isPublic() || symbol.isEnumValue());
    }

    void buildMemberReferences(TaskContext& ctx, ApiDocument& document, const bool runtime)
    {
        std::unordered_set<Utf8> ambiguous;
        for (const DocItem& item : document.items)
        {
            if (item.overloads.empty() || !item.overloads.front().symbol || !item.overloads.front().symbol->isSymMap())
                continue;

            std::vector<const Symbol*> members;
            item.overloads.front().symbol->asSymMap()->getAllSymbols(members);
            for (const Symbol* member : members)
            {
                if (!member || !canDocumentMember(ctx.compiler(), *member, runtime))
                    continue;

                const Utf8 fullName = member->getFullScopedName(ctx);
                if (fullName.empty())
                    continue;
                const Utf8 anchor = makeAnchor(fullName);
                addReference(document.references, ambiguous, fullName, anchor);
                addReference(document.references, ambiguous, lastNamePart(fullName), anchor);
            }
        }
    }

    void buildDocNamespaces(ApiDocument& document, std::vector<DocNamespace>& namespaces)
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

        std::vector<Utf8> sortedNames(names.begin(), names.end());
        std::ranges::sort(sortedNames);
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

        std::unordered_set<Utf8> ambiguous;
        for (const DocNamespace& docNamespace : namespaces)
        {
            const Utf8 anchor = std::format("namespace_{}", makeAnchor(docNamespace.fullName));
            addReference(document.references, ambiguous, docNamespace.fullName, anchor);
            addReference(document.references, ambiguous, lastNamePart(docNamespace.fullName), anchor);
        }
    }

    std::vector<Utf8> memberCommentLines(TaskContext& ctx, const Symbol& symbol)
    {
        const SourceFile* file = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!file)
            file = ctx.compiler().sourceViewFile(symbol);
        if (!file)
            return {};
        AstNodeRef declRef;
        if (!ModuleApi::Internal::tryFindNodeRef(file->ast(), symbol.decl(), declRef))
        {
            if (file->ast().hasSourceView() && symbol.srcViewRef() != file->ast().srcView().ref())
                declRef = file->ast().tryFindNodeRef(symbol.decl());
            if (declRef.isInvalid())
                return {};
        }
        const AstNodeRef  rootRef = ModuleApi::Internal::findExportDeclRoot(*file, declRef);
        std::vector<Utf8> result  = symbolCommentLines(ctx, symbol, *file, declRef, rootRef);
        if (!result.empty())
            return result;

        // A `using name: union` member is represented by its anonymous aggregate
        // declaration, whose AST end token is not the member name. Fall back to
        // the symbol token's physical line so an ordinary trailing field comment
        // remains sufficient for this source form.
        const SourceCodeRange range = symbol.codeRange(ctx);
        if (!range.srcView)
            return result;

        const std::string_view source = range.srcView->stringView();
        const size_t                 start  = std::min<size_t>(range.offset + range.len, source.size());
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
        if (commentPos != std::string_view::npos)
            appendNormalizedComment(result, suffix.substr(commentPos));
        return result;
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
            if (root && (isAnonymousAggregateSymbol(*root) || hasCompilerGeneratedIdentifier(ctx, *root)))
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

    Utf8 documentationTypeName(const RenderContext& renderCtx, const Symbol& symbol)
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

    void renderMemberTable(Utf8& content, const RenderContext& renderCtx, const Symbol& owner, const bool runtime)
    {
        if (!owner.isSymMap())
            return;

        std::vector<const Symbol*> members;
        owner.asSymMap()->getAllSymbols(members);

        struct MemberRow
        {
            Utf8              name;
            Utf8              anchor;
            Utf8              type;
            std::vector<Utf8> commentLines;
        };
        std::vector<MemberRow> fields;
        const bool             hideFields = owner.isStruct() && ModuleApi::Export::isModuleApiOpaqueType(owner);

        for (const Symbol* member : members)
        {
            if (!member || !canDocumentMember(renderCtx.ctx->compiler(), *member, runtime))
                continue;

            MemberRow row;
            row.name         = Utf8(member->name(*renderCtx.ctx));
            row.anchor       = makeAnchor(member->getFullScopedName(*renderCtx.ctx));
            row.commentLines = memberCommentLines(*renderCtx.ctx, *member);
            row.type         = documentationTypeName(renderCtx, *member);

            if (!hideFields &&
                ((owner.isEnum() && member->isEnumValue()) ||
                 ((owner.isStruct() || owner.isInterface()) && (member->isVariable() || member->isConstant()))))
            {
                fields.push_back(std::move(row));
            }
        }

        const auto rowLess = [](const MemberRow& lhs, const MemberRow& rhs) {
            return lhs.name < rhs.name;
        };
        std::ranges::sort(fields, rowLess);

        if (fields.empty())
            return;
        const bool isEnum = owner.isEnum();
        content.append(std::format("<h3>{}</h3>\n<table class=\"table-enumeration api-summary\">\n<thead><tr><th>Name</th>", isEnum ? "Cases" : "Fields"));
        if (!isEnum)
            content += "<th>Type</th>";
        content += "<th>Description</th></tr></thead>\n<tbody>\n";
        for (const MemberRow& row : fields)
        {
            content.append(std::format("<tr><td id=\"{}\" class=\"code-type\">{}</td>", row.anchor, escapeHtml(row.name)));
            if (!isEnum)
                content.append(std::format("<td class=\"code-type\">{}</td>", renderTypeName(renderCtx, row.type)));
            const std::vector<Utf8> summary = summaryLines(row.commentLines);
            content.append(std::format("<td>{}</td></tr>\n", renderMarkdownLines(renderCtx, summary)));
        }
        content += "</tbody>\n</table>\n";
    }

    void renderSummaryTable(Utf8& content, const RenderContext& renderCtx, const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items, const bool showKind, const bool shortNames)
    {
        if (items.empty())
            return;

        content.append(std::format("<h3 id=\"{}\">{}</h3>\n<table class=\"api-summary\">\n<thead><tr><th>Name</th>", anchor, escapeHtml(title)));
        if (showKind)
            content += "<th>Kind</th>";
        content += "<th>Description</th></tr></thead>\n<tbody>\n";
        for (const DocItem* item : items)
        {
            if (!item || item->overloads.empty())
                continue;
            const Utf8 name = shortNames ? lastNamePart(item->fullName) : item->displayName;
            content.append(std::format("<tr><td class=\"code-type\"><a href=\"#{}\">{}</a></td>", makeAnchor(item->fullName), escapeHtml(name)));
            if (showKind)
                content.append(std::format("<td>{}</td>", itemKindName(item->kind)));
            const std::vector<Utf8> summary = summaryLines(item->overloads.front().commentLines);
            content.append(std::format("<td>{}</td></tr>\n", renderMarkdownLines(renderCtx, summary)));
        }
        content += "</tbody>\n</table>\n";
    }

    void renderNamespaceTable(Utf8& content, const std::string_view title, const std::string_view anchor, std::span<const Utf8> namespaces)
    {
        if (namespaces.empty())
            return;
        content.append(std::format("<h3 id=\"{}\">{}</h3>\n<table class=\"api-summary\">\n<thead><tr><th>Namespace</th></tr></thead>\n<tbody>\n", anchor, escapeHtml(title)));
        for (const Utf8& name : namespaces)
            content.append(std::format("<tr><td class=\"code-type\"><a href=\"#namespace_{}\">{}</a></td></tr>\n", makeAnchor(name), escapeHtml(name)));
        content += "</tbody>\n</table>\n";
    }

    void renderNamespaceItem(Utf8& content, const RenderContext& renderCtx, const DocNamespace& docNamespace)
    {
        const Utf8 anchor = std::format("namespace_{}", makeAnchor(docNamespace.fullName));
        content += "<section class=\"api-symbol\">\n<table class=\"api-item\"><tr><td>";
        content.append(std::format("<span id=\"{}\"><span class=\"api-item-title-kind\">namespace</span> <span class=\"api-item-title-strong\">{}</span></span>", anchor, escapeHtml(docNamespace.fullName)));
        content += "</td></tr></table>\n";
        content.append(std::format("<p>Public API declared directly in <span class=\"code-inline\">{}</span>.</p>\n", escapeHtml(docNamespace.fullName)));

        std::vector<const DocItem*> types;
        std::vector<const DocItem*> enumerations;
        std::vector<const DocItem*> constants;
        std::vector<const DocItem*> functions;
        for (const DocItem* item : docNamespace.items)
        {
            switch (item->kind)
            {
                case DocItemKind::Struct:
                case DocItemKind::Interface:
                case DocItemKind::Alias:
                    types.push_back(item);
                    break;
                case DocItemKind::Enum:
                    enumerations.push_back(item);
                    break;
                case DocItemKind::Constant:
                    constants.push_back(item);
                    break;
                case DocItemKind::Function:
                case DocItemKind::Attribute:
                    functions.push_back(item);
                    break;
                case DocItemKind::Namespace:
                    break;
            }
        }

        renderNamespaceTable(content, "Namespaces", std::format("{}_namespaces", anchor), docNamespace.children);
        renderSummaryTable(content, renderCtx, "Types", std::format("{}_types", anchor), types, true, false);
        renderSummaryTable(content, renderCtx, "Enumerations", std::format("{}_enumerations", anchor), enumerations, false, false);
        renderSummaryTable(content, renderCtx, "Constants", std::format("{}_constants", anchor), constants, false, false);
        renderSummaryTable(content, renderCtx, "Functions", std::format("{}_functions", anchor), functions, false, false);
        content += "</section>\n";
    }

    void renderOwnedSymbolTables(Utf8& content, const RenderContext& renderCtx, const Utf8& ownerName, const DocItemsByOwner& itemsByOwner)
    {
        const auto ownerIt = itemsByOwner.find(ownerName);
        if (ownerIt == itemsByOwner.end())
            return;

        std::vector<const DocItem*> types;
        std::vector<const DocItem*> enumerations;
        std::vector<const DocItem*> constants;
        std::vector<const DocItem*> functions;
        for (const DocItem* item : ownerIt->second)
        {
            switch (item->kind)
            {
                case DocItemKind::Struct:
                case DocItemKind::Interface:
                case DocItemKind::Alias:
                    types.push_back(item);
                    break;
                case DocItemKind::Enum:
                    enumerations.push_back(item);
                    break;
                case DocItemKind::Constant:
                    constants.push_back(item);
                    break;
                case DocItemKind::Function:
                case DocItemKind::Attribute:
                    functions.push_back(item);
                    break;
                case DocItemKind::Namespace:
                    break;
            }
        }

        const Utf8 anchor = makeAnchor(ownerName);
        renderSummaryTable(content, renderCtx, "Nested types", std::format("{}_types", anchor), types, true, true);
        renderSummaryTable(content, renderCtx, "Enumerations", std::format("{}_enumerations", anchor), enumerations, false, true);
        renderSummaryTable(content, renderCtx, "Constants", std::format("{}_constants", anchor), constants, false, true);
        renderSummaryTable(content, renderCtx, "Methods", std::format("{}_methods", anchor), functions, false, true);
    }

    void renderDocItem(Utf8& content, RenderContext& renderCtx, const DocItem& item, const bool runtime)
    {
        if (item.overloads.empty())
            return;

        const DocOverload& first = item.overloads.front();
        const Utf8         link  = sourceLink(renderCtx.ctx->compiler(), first, runtime);

        content += "<section class=\"api-symbol\">\n";
        content += "<table class=\"api-item\"><tr><td>";
        content.append(std::format("<span id=\"{}\"><span class=\"api-item-title-kind\">{}</span> <span class=\"api-item-title-strong\">{}</span></span>", makeAnchor(item.fullName), itemKindName(item.kind), escapeHtml(item.displayName)));
        content += "</td>";
        if (!link.empty())
            content.append(std::format("<td class=\"api-item-title-src-ref\"><a href=\"{}\">[src]</a></td>", escapeHtml(link, true)));
        content += "</tr></table>\n";

        for (size_t overloadIndex = 0; overloadIndex < item.overloads.size(); ++overloadIndex)
        {
            const DocOverload& overload   = item.overloads[overloadIndex];
            renderCtx.headingAnchorPrefix = std::format("{}_{}", makeAnchor(item.fullName), overloadIndex);
            if (!overload.commentLines.empty())
                content += renderMarkdownLines(renderCtx, overload.commentLines);
            if (!overload.signature.empty() && item.kind != DocItemKind::Namespace)
                content += codeHtml(*renderCtx.ctx, renderCtx, overload.signature);
        }
        content += "</section>\n";
    }

    void renderApiDocument(TaskContext& ctx, ApiDocument& document, const PageOptions& options, const bool runtime)
    {
        buildReferences(document);
        buildMemberReferences(ctx, document, runtime);
        std::vector<DocNamespace> namespaces;
        buildDocNamespaces(document, namespaces);

        std::vector<const Symbol*>        symbols;
        std::unordered_set<const Symbol*> seenSymbols;
        if (ctx.compiler().symModule())
            collectSymbolTree(symbols, seenSymbols, *ctx.compiler().symModule());
        if (ctx.compiler().importRootNamespace())
            collectSymbolTree(symbols, seenSymbols, *ctx.compiler().importRootNamespace());
        buildExternalReferences(ctx, document, options);

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

        Utf8 moduleName = fromRuntimeString(ctx.compiler().buildCfg().moduleNamespace);
        if (moduleName.empty())
            moduleName = options.titleContent;

        RenderContext renderCtx = {
            .ctx                = &ctx,
            .options            = &options,
            .references         = &document.references,
            .externalReferences = &document.externalReferences,
            .externalModules    = &document.externalModules,
            .anonymousTypeNames = &anonymousTypeNames,
            .moduleName         = moduleName,
        };

        document.toc += "<h3>Start here</h3>\n<ul>\n<li><a href=\"#overview\">Overview</a></li>\n";
        for (const DocGuide& guide : document.guides)
            document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", guide.anchor, escapeHtml(guide.title)));
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

        const auto appendTocGroup = [&](const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items) {
            if (items.empty())
                return;
            document.toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", anchor, escapeHtml(title)));
        };
        document.toc += "<ul>\n";
        if (!namespaces.empty())
            document.toc += "<li><a href=\"#summary-namespaces\">Namespaces</a></li>\n";
        appendTocGroup("Types", "summary-types", types);
        appendTocGroup("Enumerations", "summary-enumerations", enumerations);
        appendTocGroup("Constants", "summary-constants", constants);
        appendTocGroup("Functions", "summary-functions", functions);
        document.toc += "</ul>\n";

        for (const DocGuide& guide : document.guides)
        {
            renderCtx.headingAnchorPrefix = guide.anchor;
            document.content.append(std::format("<section class=\"api-guide\"><h2 id=\"{}\">{}</h2>\n", guide.anchor, escapeHtml(guide.title)));
            document.content += renderMarkdownLines(renderCtx, guide.lines, 1);
            document.content += "</section>\n";
        }

        document.content += "<section class=\"api-overview\">\n<h2 id=\"api-reference\">API reference</h2>\n<p>Use these summaries to find the right entry point. Every linked symbol also has one standalone, fully qualified reference entry below.</p>\n";
        std::vector<Utf8> namespaceNames;
        namespaceNames.reserve(namespaces.size());
        for (const DocNamespace& docNamespace : namespaces)
            namespaceNames.push_back(docNamespace.fullName);
        renderNamespaceTable(document.content, "Namespaces", "summary-namespaces", namespaceNames);
        renderSummaryTable(document.content, renderCtx, "Types", "summary-types", types, true, false);
        renderSummaryTable(document.content, renderCtx, "Enumerations", "summary-enumerations", enumerations, false, false);
        renderSummaryTable(document.content, renderCtx, "Constants", "summary-constants", constants, false, false);
        renderSummaryTable(document.content, renderCtx, "Functions", "summary-functions", functions, false, false);
        document.content += "</section>\n<h2 id=\"detailed-reference\">Detailed reference</h2>\n";

        const auto renderGroup = [&](const std::string_view title, const std::string_view anchor, std::span<const DocItem* const> items) {
            if (items.empty())
                return;
            document.content.append(std::format("<h3 id=\"{}\">{}</h3>\n", anchor, escapeHtml(title)));
            for (const DocItem* item : items)
            {
                renderDocItem(document.content, renderCtx, *item, runtime);
                const DocOverload& first = item->overloads.front();
                renderMemberTable(document.content, renderCtx, *first.symbol, runtime);
                renderOwnedSymbolTables(document.content, renderCtx, item->fullName, itemsByOwner);
            }
        };

        if (!namespaces.empty())
        {
            document.content += "<h3 id=\"namespaces\">Namespaces</h3>\n";
            for (const DocNamespace& docNamespace : namespaces)
                renderNamespaceItem(document.content, renderCtx, docNamespace);
        }
        renderGroup("Types", "types", types);
        renderGroup("Enumerations", "enumerations", enumerations);
        renderGroup("Constants", "constants", constants);
        renderGroup("Functions", "functions", functions);
        renderGroup("Other symbols", "other-symbols", other);
    }

    Utf8 extractModuleDocComment(std::string_view source)
    {
        source = trimView(source);
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

    Utf8 defaultModuleDocComment(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->hasFlag(FileFlagsE::Module))
            {
                Utf8 result = extractModuleDocComment(file->sourceView());
                if (!result.empty())
                    return result;
            }
        }

        fs::path path = compiler.cmdLine().moduleFilePath;
        if (path.empty() && !compiler.cmdLine().modulePath.empty())
            path = compiler.cmdLine().modulePath / "module.swg";
        if (!path.empty())
        {
            std::string             source;
            FileSystem::IoErrorInfo error;
            if (FileSystem::readTextFile(path, source, error) == Result::Continue)
                return extractModuleDocComment(source);
        }
        return {};
    }
}

SWC_END_NAMESPACE();
