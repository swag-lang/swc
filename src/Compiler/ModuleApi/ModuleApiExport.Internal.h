#pragma once
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/ModuleApi/ModuleApi.Internal.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
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
    using ModuleApi::isExportedPublicDeclScope;
    using ModuleApi::isCurrentModuleSourceFile;
    using ModuleApi::isModuleApiOpaqueType;
    using ModuleApi::moduleApiNodeSourceView;
    using ModuleApi::moduleApiSnippetStartTokRef;
    using ModuleApi::sourceTokenByteEnd;
    using ModuleApi::sourceTokenByteStart;
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
    };

    struct ModuleApiValidationStack
    {
        SmallVector<const Symbol*>        values;
        std::unordered_set<const Symbol*> set;
        std::unordered_set<const Symbol*> validated;

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
    Utf8             buildModuleNamespaceName(const CompilerInstance& compiler);
    Utf8             buildModuleArtifactName(const CompilerInstance& compiler);
    bool             isCurrentModuleSymbol(const CompilerInstance& compiler, const Symbol& symbol);
    bool             isWholeFileExportedSymbol(const CompilerInstance& compiler, const Symbol& symbol);
    bool             sameNamespacePath(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs);
    std::string_view preferredLineEnding(const SourceFile& file);
    Result           writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content);

    // ModuleApiExport.Validate.cpp
    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack);
    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack);

    // ModuleApiExport.Roots.cpp
    void sortGeneratedModuleApiRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& roots);

    // ModuleApiExport.Generate.cpp
    Result     buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, std::string_view eol, Utf8& outSnippet, ModuleApiValidationStack& validationStack);
    bool       tryBuildImplPrefix(TaskContext& ctx, const SourceFile& file, AstNodeRef implRef, std::string_view eol, Utf8& outPrefix);
    bool       tryFindSemanticImplRef(TaskContext& ctx, const ModuleApiGeneratedRoot& root, AstNodeRef& outImplRef, const SourceFile*& outImplFile);
    void       appendGeneratedRootUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, ModuleApiGeneratedRoot&& root);
    void       appendGeneratedRootsForFile(TaskContext& ctx, const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots);

    // ModuleApiExport.Content.cpp
    Utf8   buildExportedModuleApiContent(const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace);
    Result writeGeneratedModuleImports(TaskContext& ctx, const fs::path& exportApiDir, std::string_view eol);
    Result buildGeneratedModuleApiSingleFileContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent);
}

SWC_END_NAMESPACE();
