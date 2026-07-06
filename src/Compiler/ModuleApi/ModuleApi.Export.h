#pragma once
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/SmallVector.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

// Internal declarations shared by the ModuleApi.Export.* translation units.
namespace ModuleApi::Export
{
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

    // Runs `fn(workerCtx, index)` for index in [0, count) across the compiler's worker
    // threads. Each worker carries its own TaskContext copy (so per-task state is isolated)
    // and grabs indices via an atomic counter. Falls back to an inline loop when the job
    // manager is single-threaded or there is a single item. The caller is responsible for
    // ensuring `fn` only touches immutable (post-sema) data plus thread-safe services
    // (type interning, diagnostics) and writes exclusively to its own `index` slot.
    template<typename T>
    void parallelForIndexed(TaskContext& ctx, uint32_t count, const T& fn)
    {
        if (count == 0)
            return;

        JobManager& jobMgr = ctx.global().jobMgr();
        if (count == 1 || jobMgr.isSingleThreaded() || jobMgr.numWorkers() == 0)
        {
            for (uint32_t i = 0; i < count; ++i)
                fn(ctx, i);
            return;
        }

        class WorkerJob final : public Job
        {
        public:
            WorkerJob(const TaskContext& ctx, std::atomic<uint32_t>& next, uint32_t count, const T& fn) :
                Job(ctx, JobKind::ModuleApiExport),
                next_(&next),
                count_(count),
                fn_(&fn)
            {
            }

            JobResult exec() override
            {
                for (uint32_t i = next_->fetch_add(1, std::memory_order_relaxed); i < count_; i = next_->fetch_add(1, std::memory_order_relaxed))
                    (*fn_)(ctx(), i);
                return JobResult::Done;
            }

        private:
            std::atomic<uint32_t>* next_;
            uint32_t               count_;
            const T*               fn_;
        };

        const uint32_t        numWorkers = std::min(count, jobMgr.numWorkers());
        const JobClientId     clientId   = ctx.compiler().jobClientId();
        std::atomic<uint32_t> nextIndex{0};

        std::vector<std::unique_ptr<WorkerJob>> jobs;
        jobs.reserve(numWorkers);
        for (uint32_t i = 0; i < numWorkers; ++i)
            jobs.push_back(std::make_unique<WorkerJob>(ctx, nextIndex, count, fn));
        for (auto& job : jobs)
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        jobMgr.waitAll(clientId);
    }

    // ModuleApi.Export.cpp
    Utf8             buildModuleNamespaceName(const CompilerInstance& compiler);
    Utf8             buildModuleArtifactName(const CompilerInstance& compiler);
    bool             isCurrentModuleSymbol(const CompilerInstance& compiler, const Symbol& symbol);
    bool             isModuleApiOpaqueType(const Symbol& symbol);
    bool             isWholeFileExportedSymbol(const CompilerInstance& compiler, const Symbol& symbol);
    bool             sameNamespacePath(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs);
    std::string_view preferredLineEnding(const SourceFile& file);
    uint32_t         sourceTokenByteStart(const SourceView& srcView, const Token& token);
    uint32_t         sourceTokenByteEnd(const SourceView& srcView, const Token& token);
    Result           writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content);

    // ModuleApi.Export.Validate.cpp
    Result validatePublicTypeSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiValidationStack& stack);
    Result validatePublicFunctionSymbol(TaskContext& ctx, const SymbolFunction& symbolFunction, ModuleApiValidationStack& stack);

    // ModuleApi.Export.Roots.cpp
    void sortGeneratedModuleApiRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& roots);

    // ModuleApi.Export.Snippet.cpp
    const SourceView& moduleApiNodeSourceView(TaskContext& ctx, const Ast& ast, AstNodeRef nodeRef);
    TokenRef          moduleApiSnippetStartTokRef(const Ast& ast, const AstNode& node);
    bool              tryGetModuleApiSnippetOffsets(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset, uint32_t& outEndOffset);
    bool              tryGetModuleApiSnippetStartOffset(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset);
    bool              tryGetModuleApiSnippet(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, std::string_view& outSnippet);
    Utf8              buildSanitizedModuleApiSnippet(TaskContext& ctx, const SourceFile& file, AstNodeRef nodeRef, uint32_t startOffset, std::string_view snippetText, std::string_view eol);

    // ModuleApi.Export.Generate.cpp
    Result     buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, std::string_view eol, Utf8& outSnippet, ModuleApiValidationStack& validationStack);
    bool       tryBuildImplPrefix(TaskContext& ctx, const SourceFile& file, AstNodeRef implRef, std::string_view eol, Utf8& outPrefix);
    AstNodeRef findEnclosingImplRef(const SourceFile& file, AstNodeRef declRef);
    bool       tryFindSemanticImplRef(TaskContext& ctx, const ModuleApiGeneratedRoot& root, AstNodeRef& outImplRef, const SourceFile*& outImplFile);
    void       appendGeneratedRootUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, ModuleApiGeneratedRoot&& root);
    void       appendGeneratedRootsForFile(TaskContext& ctx, const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots);

    // ModuleApi.Export.Content.cpp
    Utf8   buildExportedModuleApiContent(const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace);
    Result writeGeneratedModuleImports(TaskContext& ctx, const fs::path& exportApiDir, std::string_view eol);
    Result buildGeneratedModuleApiSingleFileContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent);
}

SWC_END_NAMESPACE();
