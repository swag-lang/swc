#pragma once
#include "Compiler/ModuleApi/ModuleApi.Internal.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

// Private declarations shared by the ModuleApiExport.* translation units.
namespace ModuleApiExport
{
    using ModuleApi::buildSanitizedModuleApiSnippet;
    using ModuleApi::extractPublicNamespacePath;
    using ModuleApi::findEnclosingImplRef;
    using ModuleApi::findExportDeclRoot;
    using ModuleApi::isCurrentModuleSourceFile;
    using ModuleApi::isCurrentModuleSymbol;
    using ModuleApi::isExportedPublicDeclScope;
    using ModuleApi::isModuleApiOpaqueType;
    using ModuleApi::moduleApiNodeSourceView;
    using ModuleApi::moduleApiSnippetStartTokRef;
    using ModuleApi::sameNamespacePath;
    using ModuleApi::tryFindReachableNodeRef;
    using ModuleApi::tryGetModuleApiSnippet;
    using ModuleApi::tryGetModuleApiSnippetOffsets;
    using ModuleApi::tryGetModuleApiSnippetStartOffset;

    struct ModuleApiGeneratedRoot
    {
        const SourceFile*          file    = nullptr;
        AstNodeRef                 nodeRef = AstNodeRef::invalid();
        const Symbol*              symbol  = nullptr;
        std::vector<IdentifierRef> namespacePath;
        // A non-public declaration published because a source body in the interface names it.
        // It keeps its own access and its body: the module does not export it, so a foreign
        // binding could not reach it.
        bool supporting = false;
    };

    struct ModuleApiValidationStack
    {
        SmallVector<const Symbol*>        values;
        std::unordered_set<const Symbol*> set;
        // Only ever added to, so a flat table rather than a map node per symbol.
        PointerSet<const Symbol> validated;
        // The supporting symbols of the interface being built; a non-public type among them
        // is as reachable as a public one.
        const PointerSet<const Symbol>* supportingSymbols = nullptr;

        bool isSupporting(const Symbol& symbol) const
        {
            return supportingSymbols && supportingSymbols->contains(&symbol);
        }

        bool contains(const Symbol& symbol) const
        {
            return set.contains(&symbol);
        }

        bool isValidated(const Symbol& symbol) const
        {
            return validated.contains(&symbol);
        }

        void markValidated(const Symbol& symbol)
        {
            validated.insert(&symbol);
        }

        void push(const Symbol& symbol)
        {
            values.push_back(&symbol);
            set.insert(&symbol);
        }

        void pop()
        {
            const Symbol* symbol = values.back();
            values.pop_back();
            set.erase(symbol);
        }
    };

    // ModuleApiExport.cpp
    Utf8             buildModuleArtifactName(const CompilerInstance& compiler);
    bool             isWholeFileExportedSymbol(const CompilerInstance& compiler, const Symbol& symbol);
    std::string_view preferredLineEnding(const SourceFile& file);
    Result           writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content);

    // ModuleApiExport.Validate.cpp
    Utf8   symbolKindName(const Symbol& symbol);
    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack);
    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack);

    // ModuleApiExport.Roots.cpp
    enum class ModuleApiDependencyScope : uint8_t
    {
        Public,
        NonPublic,
        Any,
    };

    // The type symbols of the current module that a symbol's declaration names: the owner of a
    // method, the generic arguments of an instance, a signature, a field, an alias target.
    struct ModuleApiDependencyCollector
    {
        TaskContext*               ctx;
        ModuleApiDependencyScope   scope = ModuleApiDependencyScope::Public;
        std::vector<const Symbol*> symbols;
        // Membership only: one collector per root, so the sets stay small and flat.
        PointerSet<const Symbol> symbolSet;
        PointerSet<const Symbol> visitedSymbols;
        RefSet<TypeRef>          visitedTypeRefs;
    };

    void collectModuleApiSymbolDependencies(ModuleApiDependencyCollector& collector, const Symbol& symbol);
    void sortGeneratedModuleApiRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& roots);

    // ModuleApiExport.Supporting.cpp
    Result appendSupportingDeclarationRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& ioRoots);

    // ModuleApiExport.Generate.cpp
    Result validateWholeFileFunctionBodies(TaskContext& ctx, const SourceFile& file);
    Result buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, std::string_view eol, Utf8& outSnippet, ModuleApiValidationStack& validationStack);
    bool   tryBuildImplPrefix(TaskContext& ctx, const SourceFile& file, AstNodeRef implRef, std::string_view eol, Utf8& outPrefix);
    bool   tryFindSemanticImplRef(TaskContext& ctx, const ModuleApiGeneratedRoot& root, AstNodeRef& outImplRef, const SourceFile*& outImplFile);
    void   appendGeneratedRootUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, ModuleApiGeneratedRoot&& root);
    void   mergeGeneratedRootsUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, std::vector<std::vector<ModuleApiGeneratedRoot>>& perFileRoots);
    void   appendGeneratedRootsForFile(TaskContext& ctx, const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots);

    // ModuleApiExport.Content.cpp
    void   removeModuleApiAttributes(TaskContext& ctx, Utf8& ioContent, std::span<const std::string_view> attributeNames);
    Utf8   buildExportedModuleApiContent(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace);
    Result writeGeneratedModuleImports(TaskContext& ctx, const fs::path& exportApiDir, std::string_view eol);
    Result buildGeneratedModuleApiSingleFileContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent);
}

SWC_END_NAMESPACE();
