#include "pch.h"
#include "Compiler/ModuleApi/ModuleApiExport.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

// A generic body, a macro and a mixin travel as source and are analyzed again by every
// importer, so each name they spell has to resolve in the generated file. The module may keep
// such a declaration private or internal: this pass publishes it with that access, then
// publishes what the published declaration needs in turn.
//
// An unmaterialized body has no resolved symbols, so its names are looked up the way the
// importer will look them up: in the declaring type and its impl blocks, in the enclosing
// namespaces, and in the private root of the file. That over-approximates (a local can share
// the name of a private helper), which costs an unused declaration in the interface; the
// resolved bodies of the published helpers are then followed exactly.
namespace
{
    using ModuleApiExport::appendGeneratedRootUnique;
    using ModuleApiExport::collectModuleApiSymbolDependencies;
    using ModuleApiExport::extractPublicNamespacePath;
    using ModuleApiExport::findExportDeclRoot;
    using ModuleApiExport::isCurrentModuleSymbol;
    using ModuleApiExport::isExportedPublicDeclScope;
    using ModuleApiExport::isModuleApiOpaqueType;
    using ModuleApiExport::isWholeFileExportedSymbol;
    using ModuleApiExport::ModuleApiDependencyCollector;
    using ModuleApiExport::ModuleApiDependencyScope;
    using ModuleApiExport::ModuleApiGeneratedRoot;
    using ModuleApiExport::moduleApiNodeSourceView;
    using ModuleApiExport::tryFindReachableNodeRef;

    struct SupportingCollector
    {
        TaskContext*                         ctx;
        std::vector<ModuleApiGeneratedRoot>* roots;
        // Every root symbol, public or supporting: what the generated file already declares.
        PointerSet<const Symbol> published;
        // Supporting roots whose own dependencies are not collected yet.
        std::vector<size_t> pending;
    };

    Utf8 supportingSymbolKindName(const Symbol& symbol)
    {
        if (const auto* function = symbol.safeCast<SymbolFunction>())
            return function->isMethod() ? Utf8("method") : Utf8("function");
        return ModuleApiExport::symbolKindName(symbol);
    }

    void addDependencyDeclaredHereNote(TaskContext& ctx, Diagnostic& diag, const Symbol& referencedSymbol)
    {
        diag.addNote(DiagnosticId::cmd_note_api_dependency_declared_here);
        diag.last().addArgument(Diagnostic::ARG_TARGET, referencedSymbol.getFullScopedName(ctx));
        diag.last().addSpan(referencedSymbol.codeRange(ctx));
    }

    Result reportSupportingDeclarationError(TaskContext& ctx, const Symbol& symbol, const SourceCodeRange& range, std::string_view because, const Symbol* referencedSymbol)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_supporting_decl_not_exportable, ctx.compiler().srcView(symbol.srcViewRef()).fileRef());
        diag.addArgument(Diagnostic::ARG_WHAT, supportingSymbolKindName(symbol));
        diag.addArgument(Diagnostic::ARG_SYM, symbol.getFullScopedName(ctx));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.last().addSpan(range, "", DiagnosticSeverity::Error);
        if (referencedSymbol)
            addDependencyDeclaredHereNote(ctx, diag, *referencedSymbol);
        diag.report(ctx);
        return Result::Error;
    }

    // Whether the symbol is a declaration the generated file can carry as source.
    bool isPublishableSupportingSymbol(TaskContext& ctx, const Symbol& symbol)
    {
        if (symbol.isPublic() || !isCurrentModuleSymbol(ctx.compiler(), symbol) || isWholeFileExportedSymbol(ctx.compiler(), symbol))
            return false;
        if (!symbol.decl())
            return false;

        if (const auto* function = symbol.safeCast<SymbolFunction>())
        {
            if (function->isGenericInstance() || function->attributes().hasRtFlag(RtAttributeFlagsE::PlaceHolder))
                return false;
            if (const SymbolStruct* owner = function->ownerStruct(); owner && owner->isGenericInstance())
                return false;
            return function->decl()->is(AstNodeId::FunctionDecl);
        }

        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            return !symbolStruct->isGenericInstance();

        // A member constant travels with the type that declares it.
        if (symbol.isConstant())
        {
            const SymbolMap* owner = symbol.ownerSymMap();
            return !owner || (!owner->isStruct() && !owner->isEnum() && !owner->isInterface());
        }

        return symbol.isEnum() || symbol.isAlias() || symbol.isInterface();
    }

    bool tryBuildSupportingRoot(TaskContext& ctx, const Symbol& symbol, ModuleApiGeneratedRoot& outRoot)
    {
        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        const SourceFile* astFile    = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!astFile)
            astFile = sourceFile;
        if (!sourceFile || !astFile)
            return false;

        AstNodeRef declRef;
        if (!tryFindReachableNodeRef(astFile->ast(), symbol.decl(), declRef))
            return false;
        if (!isExportedPublicDeclScope(*astFile, declRef, symbol))
            return false;

        outRoot.file       = astFile;
        outRoot.nodeRef    = findExportDeclRoot(*astFile, declRef);
        outRoot.symbol     = &symbol;
        outRoot.supporting = true;
        if (outRoot.nodeRef.isInvalid())
            return false;
        return extractPublicNamespacePath(ctx, *astFile, declRef, symbol, outRoot.namespacePath);
    }

    // Publishes a non-public declaration; false when the generated file cannot carry it.
    bool addSupportingSymbol(SupportingCollector& collector, const Symbol& symbol)
    {
        if (collector.published.contains(&symbol))
            return true;
        if (!isPublishableSupportingSymbol(*collector.ctx, symbol))
            return false;

        ModuleApiGeneratedRoot root;
        if (!tryBuildSupportingRoot(*collector.ctx, symbol, root))
            return false;

        collector.published.insert(&symbol);
        const size_t count = collector.roots->size();
        appendGeneratedRootUnique(*collector.roots, std::move(root));
        if (collector.roots->size() != count)
            collector.pending.push_back(count);
        return true;
    }

    // The type whose bodies a member belongs to, once the member is a field or a constant.
    const SymbolMap* owningTypeOfMember(const Symbol& symbol)
    {
        if (!symbol.isValueExpr())
            return nullptr;

        for (const SymbolMap* owner = symbol.ownerSymMap(); owner; owner = owner->ownerSymMap())
        {
            if (owner->isStruct() || owner->isEnum())
                return owner;
        }

        return nullptr;
    }

    bool needsSyntacticWalk(const Symbol& symbol)
    {
        if (const auto* function = symbol.safeCast<SymbolFunction>())
            return function->hasUnmaterializedGenericBody() || function->attributes().hasRtFlag(RtAttributeFlagsE::Macro | RtAttributeFlagsE::Mixin);
        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
            return symbolStruct->isGenericRoot() && !symbolStruct->isGenericInstance();
        return false;
    }

    // ------------------------------------------------------------------------------------------
    // Syntactic walk: an unmaterialized body, looked up by name.
    // ------------------------------------------------------------------------------------------

    using LookupScopes = SmallVector<const SymbolMap*, 16>;

    void addLookupScope(LookupScopes& scopes, const SymbolMap* symMap)
    {
        if (symMap && std::ranges::find(scopes, symMap) == scopes.end())
            scopes.push_back(symMap);
    }

    // The map of the type itself and every impl block, which is where its methods live.
    void addTypeLookupScopes(LookupScopes& scopes, const Symbol* type)
    {
        if (!type)
            return;

        if (const auto* symbolStruct = type->safeCast<SymbolStruct>())
        {
            addLookupScope(scopes, symbolStruct);
            for (const SymbolImpl* symImpl : symbolStruct->impls())
                addLookupScope(scopes, symImpl);
            return;
        }

        if (const auto* symbolEnum = type->safeCast<SymbolEnum>())
        {
            addLookupScope(scopes, symbolEnum);
            for (const SymbolImpl* symImpl : symbolEnum->impls())
                addLookupScope(scopes, symImpl);
            return;
        }

        if (type->isSymMap())
            addLookupScope(scopes, type->asSymMap());
    }

    void addImplLookupScopes(LookupScopes& scopes, const SymbolImpl& symImpl)
    {
        addLookupScope(scopes, &symImpl);
        if (symImpl.isForStruct())
            addTypeLookupScopes(scopes, symImpl.symStruct());
        else if (symImpl.isForEnum())
            addTypeLookupScopes(scopes, symImpl.symEnum());
        if (symImpl.symInterface())
            addTypeLookupScopes(scopes, symImpl.symInterface());
    }

    // Name lookup as the importer will perform it: the declaring type and its impl blocks, the
    // enclosing namespaces up to the module, then the private root of the file along the same path.
    void collectLexicalLookupScopes(LookupScopes& scopes, const ModuleApiGeneratedRoot& root)
    {
        const Symbol& symbol = *root.symbol;
        if (const auto* function = symbol.safeCast<SymbolFunction>())
        {
            if (const SymbolImpl* symImpl = function->declImplContext())
                addImplLookupScopes(scopes, *symImpl);
        }

        for (const SymbolMap* symMap = symbol.ownerSymMap(); symMap; symMap = symMap->ownerSymMap())
        {
            if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
                addImplLookupScopes(scopes, *symImpl);
            else
                addLookupScope(scopes, symMap);
            if (symMap->isModule())
                break;
        }

        const SymbolNamespace* fileNamespace = root.file ? root.file->fileNamespace() : nullptr;
        if (!fileNamespace)
            return;

        addLookupScope(scopes, fileNamespace);
        const SymbolMap* symMap = fileNamespace;
        for (const IdentifierRef idRef : root.namespacePath)
        {
            const Symbol* nested = symMap->findFirstNamespace(idRef);
            if (!nested)
                break;
            symMap = nested->asSymMap();
            addLookupScope(scopes, symMap);
        }
    }

    // Publishes what the name denotes in the scopes, and collects the types and namespaces it
    // can denote so a qualified name can continue inside them.
    void lookupSupportingName(SupportingCollector& collector, std::span<const SymbolMap* const> scopes, const IdentifierRef idRef, LookupScopes* outQualifierScopes)
    {
        for (const SymbolMap* scope : scopes)
        {
            scope->forEachSymbolById(idRef, false, [&](const Symbol* symbol) {
                addSupportingSymbol(collector, *symbol);
                if (outQualifierScopes && symbol->isSymMap() && !symbol->isImpl())
                    addTypeLookupScopes(*outQualifierScopes, symbol);
            });
        }
    }

    struct SyntacticWalk
    {
        SupportingCollector* collector;
        const Ast*           ast;
        LookupScopes         scopes;
        IdentifierRef        moduleIdRef = IdentifierRef::invalid();
        const SymbolMap*     moduleMap   = nullptr;
    };

    IdentifierRef identifierRefOf(const SyntacticWalk& walk, const AstNodeRef nodeRef, const AstNode& node)
    {
        const SourceView&      srcView = moduleApiNodeSourceView(*walk.collector->ctx, *walk.ast, nodeRef);
        const std::string_view name    = srcView.tokenString(node.tokRef());
        return name.empty() ? IdentifierRef::invalid() : walk.collector->ctx->idMgr().addIdentifier(name);
    }

    // The types and namespaces a qualifier expression can denote: 'A' in 'A.b', 'A.B' in 'A.B.c'.
    void collectQualifierScopes(SyntacticWalk& walk, const AstNodeRef nodeRef, LookupScopes& outScopes)
    {
        if (nodeRef.isInvalid() || !walk.ast->hasNode(nodeRef))
            return;

        const AstNode& node = walk.ast->node(nodeRef);
        if (node.is(AstNodeId::Identifier))
        {
            const IdentifierRef idRef = identifierRefOf(walk, nodeRef, node);
            if (idRef.isInvalid())
                return;
            if (idRef == walk.moduleIdRef)
                addLookupScope(outScopes, walk.moduleMap);
            lookupSupportingName(*walk.collector, walk.scopes.span(), idRef, &outScopes);
            return;
        }

        if (const auto* access = node.safeCast<AstMemberAccessExpr>())
        {
            LookupScopes leftScopes;
            collectQualifierScopes(walk, access->nodeLeftRef, leftScopes);
            if (leftScopes.empty() || access->nodeRightRef.isInvalid() || !walk.ast->hasNode(access->nodeRightRef))
                return;

            const AstNode& right = walk.ast->node(access->nodeRightRef);
            if (!right.is(AstNodeId::Identifier))
                return;

            const IdentifierRef idRef = identifierRefOf(walk, access->nodeRightRef, right);
            if (idRef.isValid())
                lookupSupportingName(*walk.collector, leftScopes.span(), idRef, &outScopes);
        }
    }

    void walkSourceDeclaration(SyntacticWalk& walk, const AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || !walk.ast->hasNode(nodeRef))
            return;

        const AstNode& node = walk.ast->node(nodeRef);
        if (node.is(AstNodeId::Identifier))
        {
            const IdentifierRef idRef = identifierRefOf(walk, nodeRef, node);
            if (idRef.isValid())
                lookupSupportingName(*walk.collector, walk.scopes.span(), idRef, nullptr);
            return;
        }

        if (const auto* access = node.safeCast<AstMemberAccessExpr>())
        {
            // 'Qualifier.name' looks the name up inside what the qualifier denotes; the qualifier
            // itself is still walked, so a value expression on the left is covered too.
            LookupScopes qualifierScopes;
            collectQualifierScopes(walk, access->nodeLeftRef, qualifierScopes);
            walkSourceDeclaration(walk, access->nodeLeftRef);
            if (!qualifierScopes.empty() && access->nodeRightRef.isValid() && walk.ast->hasNode(access->nodeRightRef))
            {
                const AstNode& right = walk.ast->node(access->nodeRightRef);
                if (right.is(AstNodeId::Identifier))
                {
                    const IdentifierRef idRef = identifierRefOf(walk, access->nodeRightRef, right);
                    if (idRef.isValid())
                        lookupSupportingName(*walk.collector, qualifierScopes.span(), idRef, nullptr);
                    return;
                }
            }

            walkSourceDeclaration(walk, access->nodeRightRef);
            return;
        }

        SmallVector<AstNodeRef> childRefs;
        node.collectChildrenFromAst(childRefs, *walk.ast);
        for (const AstNodeRef childRef : childRefs)
            walkSourceDeclaration(walk, childRef);
    }

    void collectSyntacticDependencies(SupportingCollector& collector, const ModuleApiGeneratedRoot& root)
    {
        SyntacticWalk walk{.collector = &collector, .ast = &root.file->ast()};
        collectLexicalLookupScopes(walk.scopes, root);
        if (const SymbolNamespace* moduleNamespace = root.file->moduleNamespace())
        {
            walk.moduleIdRef = moduleNamespace->idRef();
            walk.moduleMap   = moduleNamespace;
        }

        walkSourceDeclaration(walk, root.nodeRef);
    }

    // ------------------------------------------------------------------------------------------
    // Resolved walk: the declaration of a published helper, followed exactly.
    // ------------------------------------------------------------------------------------------

    // A node that introduces the symbols it resolves to: what it declares travels with the body.
    bool isLocalDeclarationNode(const AstNode& node)
    {
        switch (node.id())
        {
            case AstNodeId::SingleVarDecl:
            case AstNodeId::MultiVarDecl:
            case AstNodeId::VarDeclDestructuring:
            case AstNodeId::IfVarDecl:
            case AstNodeId::WithVarDecl:
            case AstNodeId::ForStmt:
            case AstNodeId::ForeachStmt:
            case AstNodeId::ForCStyleStmt:
            case AstNodeId::ParallelForStmt:
            case AstNodeId::SwitchCaseStmt:
            case AstNodeId::ErrorManagementStmt:
            case AstNodeId::FunctionDecl:
            case AstNodeId::FunctionParamMe:
            case AstNodeId::LambdaParam:
            case AstNodeId::ClosureArgument:
            case AstNodeId::GenericParamType:
            case AstNodeId::GenericParamValue:
            case AstNodeId::StructDecl:
            case AstNodeId::UnionDecl:
            case AstNodeId::AnonymousStructDecl:
            case AstNodeId::AnonymousUnionDecl:
            case AstNodeId::EnumDecl:
            case AstNodeId::EnumValue:
            case AstNodeId::AliasDecl:
            case AstNodeId::InterfaceDecl:
                return true;
            default:
                return false;
        }
    }

    bool isSupportingSymbolAvailable(SupportingCollector& collector, const PointerSet<const Symbol>& localSymbols, const Symbol& symbol)
    {
        if (symbol.isNamespace() || localSymbols.contains(&symbol))
            return true;

        // A variable is a global, a member, or a binding of the body: only the first two can
        // be unavailable, and a member is judged with its type below.
        if (const auto* variable = symbol.safeCast<SymbolVariable>())
        {
            if (!variable->hasGlobalStorage() && !owningTypeOfMember(symbol))
                return true;
        }

        if (!isCurrentModuleSymbol(collector.ctx->compiler(), symbol) || isWholeFileExportedSymbol(collector.ctx->compiler(), symbol))
            return true;
        if (symbol.isPublic() || collector.published.contains(&symbol))
            return true;

        // A field, a member constant and an enum value travel with their type.
        if (const SymbolMap* owningType = owningTypeOfMember(symbol))
        {
            if (isModuleApiOpaqueType(*owningType))
                return false;
            return owningType->isPublic() || addSupportingSymbol(collector, *owningType);
        }

        return addSupportingSymbol(collector, symbol);
    }

    // A name a published declaration resolves to, which the interface cannot carry.
    struct UnavailableSymbol
    {
        const Symbol*   symbol = nullptr;
        SourceCodeRange focus;
    };

    // Publishes what the declaration at 'nodeRef' names, and returns the first name it cannot.
    UnavailableSymbol collectResolvedNodeDependencies(SupportingCollector& collector, const SourceFile& file, AstNodeRef nodeRef)
    {
        const Ast&               ast = file.ast();
        UnavailableSymbol        result;
        PointerSet<const Symbol> localSymbols;
        Ast::visit(ast, nodeRef, [&](const AstNodeRef childRef, const AstNode& node) {
            const NodePayload::ResolvedSymbols resolved = file.nodePayloadContext().resolveSymbols(childRef);
            if (isLocalDeclarationNode(node))
            {
                for (const Symbol* symbol : resolved.symbols)
                {
                    if (symbol)
                        localSymbols.insert(symbol);
                }

                return Ast::VisitResult::Continue;
            }

            const Symbol* unavailable = nullptr;
            for (const Symbol* symbol : resolved.symbols)
            {
                if (symbol && !isSupportingSymbolAvailable(collector, localSymbols, *symbol))
                {
                    unavailable = symbol;
                    break;
                }
            }

            if (!unavailable)
            {
                const Symbol* folded = file.nodePayloadContext().foldedSourceSymbol(childRef);
                if (folded && !isSupportingSymbolAvailable(collector, localSymbols, *folded))
                    unavailable = folded;
            }

            if (!unavailable)
                return Ast::VisitResult::Continue;

            const AstNode& focus = node.is(AstNodeId::CallExpr) ? ast.node(node.cast<AstCallExpr>().nodeExprRef) : node;
            result.symbol        = unavailable;
            result.focus         = focus.codeRange(*collector.ctx);
            return Ast::VisitResult::Stop;
        });
        return result;
    }

    Utf8 notExposedBecause(TaskContext& ctx, const Symbol& symbol)
    {
        return std::format("symbol '{}' is not exposed by the module API", symbol.getFullScopedName(ctx));
    }

    Result collectResolvedDependencies(SupportingCollector& collector, const ModuleApiGeneratedRoot& root)
    {
        const UnavailableSymbol unavailable = collectResolvedNodeDependencies(collector, *root.file, root.nodeRef);
        if (!unavailable.symbol)
            return Result::Continue;

        const Utf8 because = notExposedBecause(*collector.ctx, *unavailable.symbol);
        return reportSupportingDeclarationError(*collector.ctx, *root.symbol, unavailable.focus, because.view(), unavailable.symbol);
    }

    // An importer lays out a public struct from the interface, internal fields included. What
    // those fields name is layout, not API: it travels as supporting declarations.
    Result collectInternalFieldDependencies(SupportingCollector& collector, const ModuleApiGeneratedRoot& root)
    {
        const SymbolStruct* symbolStruct = root.symbol ? root.symbol->safeCast<SymbolStruct>() : nullptr;
        if (!root.file || !symbolStruct || symbolStruct->isGenericRoot() || isModuleApiOpaqueType(*symbolStruct))
            return Result::Continue;

        TaskContext& ctx = *collector.ctx;
        for (const SymbolVariable* field : symbolStruct->fields())
        {
            if (!field || field->isIgnored() || field->memberAccess() == MemberAccess::Public || !field->decl())
                continue;

            AstNodeRef fieldRef;
            if (!tryFindReachableNodeRef(root.file->ast(), field->decl(), fieldRef))
                continue;

            const UnavailableSymbol unavailable = collectResolvedNodeDependencies(collector, *root.file, fieldRef);
            if (!unavailable.symbol)
                continue;

            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_internal_field_not_exportable, ctx.compiler().srcView(symbolStruct->srcViewRef()).fileRef());
            diag.addArgument(Diagnostic::ARG_SYM, symbolStruct->getFullScopedName(ctx));
            diag.addArgument(Diagnostic::ARG_VALUE, field->name(ctx));
            diag.addArgument(Diagnostic::ARG_BECAUSE, notExposedBecause(ctx, *unavailable.symbol));
            diag.last().addSpan(unavailable.focus, "", DiagnosticSeverity::Error);
            addDependencyDeclaredHereNote(ctx, diag, *unavailable.symbol);
            diag.report(ctx);
            return Result::Error;
        }

        return Result::Continue;
    }

    // The signature, fields and targets of a published helper name types the interface has to carry.
    void collectTypeDependencies(SupportingCollector& collector, const Symbol& symbol)
    {
        ModuleApiDependencyCollector dependencies{.ctx = collector.ctx, .scope = ModuleApiDependencyScope::NonPublic};
        collectModuleApiSymbolDependencies(dependencies, symbol);
        for (const Symbol* dependency : dependencies.symbols)
            addSupportingSymbol(collector, *dependency);
    }
}

namespace ModuleApiExport
{
    Result appendSupportingDeclarationRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& ioRoots)
    {
        SupportingCollector collector{.ctx = &ctx, .roots = &ioRoots};
        for (const ModuleApiGeneratedRoot& root : ioRoots)
        {
            if (root.symbol)
                collector.published.insert(root.symbol);
        }

        // Public roots seed the walk; only a body that travels unresolved can name something
        // the export did not already validate.
        const size_t publicCount = ioRoots.size();
        for (size_t index = 0; index < publicCount; ++index)
        {
            const ModuleApiGeneratedRoot& root = ioRoots[index];
            if (root.file && root.symbol && needsSyntacticWalk(*root.symbol))
                collectSyntacticDependencies(collector, root);
        }

        for (size_t index = 0; index < publicCount; ++index)
        {
            // Copy: the roots vector grows while the fields' dependencies are published.
            const ModuleApiGeneratedRoot root = ioRoots[index];
            SWC_RESULT(collectInternalFieldDependencies(collector, root));
        }

        while (!collector.pending.empty())
        {
            const size_t index = collector.pending.back();
            collector.pending.pop_back();

            // Copy: the roots vector grows while the dependencies of a root are published.
            const ModuleApiGeneratedRoot root = ioRoots[index];
            collectTypeDependencies(collector, *root.symbol);
            if (needsSyntacticWalk(*root.symbol))
                collectSyntacticDependencies(collector, root);
            else
                SWC_RESULT(collectResolvedDependencies(collector, root));
        }

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
