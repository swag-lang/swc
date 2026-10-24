#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        // Collect files
        if (compiler.cmdLine().scriptMode)
        {
            if (compiler.runModuleSetup(ctx) == Result::Error)
                return;
            if (compiler.collectFiles(ctx) == Result::Error)
                return;
        }
        else
        {
            SWC_SCHED_PHASE(jobMgr, "module setup");
            if (compiler.collectFiles(ctx) == Result::Error)
                return;
            if (compiler.runModuleSetup(ctx) == Result::Error)
                return;
        }

        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Sema))
            stage.emplace(ctx, ScopedTimedLog::Stage::Sema);

        std::vector<SourceFile*> inputFiles;
        inputFiles.reserve(compiler.files().size());
        for (SourceFile* f : compiler.files())
        {
            if (!f)
                continue;
            if (!compiler.cmdLine().moduleFilePath.empty() && f->hasFlag(FileFlagsE::Module))
                continue;
            inputFiles.push_back(f);
        }

        std::vector<SourceFile*> parseFiles = inputFiles;
        if (isEditorServiceCommand(compiler.cmdLine().command))
            parseFiles = compiler.beginEditorAnalysisRevision(inputFiles);

        // Parser
        const uint64_t         errorsBefore  = Stats::getNumErrors();
        const ParserJobOptions parserOptions = {
            .emitTrivia = compiler.cmdLine().command == CommandKind::Doc,
        };
        {
            SWC_SCHED_PHASE(jobMgr, "parse");
            parseSourceFiles(ctx, parseFiles, parserOptions);
        }
        // Parsing consumes the dependency's already published API snapshot.
        // Semantic analysis can execute its native code, so join before it starts,
        // including when parsing reported an error that must drain the pipeline.
        if (compiler.completeWorkspaceDependency() != Result::Continue)
            return;
        // An editor index can still use semantic data from files that parsed successfully.
        // Files with parser errors are filtered below; regular compilation remains fail-fast.
        const bool editorIndex = !compiler.cmdLine().editorIndex.empty();
        if (Stats::getNumErrors() != errorsBefore && !editorIndex)
            return;

        // Filter files
        std::vector<SourceFile*> files;
        files.reserve(parseFiles.size());
        for (SourceFile* f : parseFiles)
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            if (!srcView.runsSema())
                continue;
            if (f->hasError())
                continue;
            files.push_back(f);
        }

        SmallVector<Ast*> moduleAsts;
        moduleAsts.reserve(inputFiles.size());
        if (isEditorServiceCommand(compiler.cmdLine().command))
        {
            for (SourceFile* f : inputFiles)
            {
                if (!f || !f->isEditorActive() || !f->ast().hasSourceView() || !f->ast().root().isValid() || f->hasError())
                    continue;
                const SourceView& srcView = f->ast().srcView();
                if (!srcView.mustSkip() && srcView.runsSema())
                    moduleAsts.push_back(&f->ast());
            }
        }
        else
        {
            for (SourceFile* f : files)
                moduleAsts.push_back(&f->ast());
        }
        SWC_SCHED_PHASE(jobMgr, "sema setup");
        Parser::finalizeAutoInlineCandidates(moduleAsts.span());

        if (compiler.setupSema(ctx) == Result::Error)
            return;
        if (compiler.validateAllocatorConfig(ctx) == Result::Error)
            return;

        SymbolNamespace* moduleNamespace = compiler.moduleNamespace();
        if (!moduleNamespace)
        {
            auto* symModule           = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            Utf8  moduleNamespaceName = compiler.moduleNamespaceName();

            constexpr SymbolFlags namespaceFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
            const IdentifierRef   idRef          = ctx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
            moduleNamespace                      = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
            symModule->addSingleSymbol(ctx, moduleNamespace);
            compiler.setSymModule(symModule);
            compiler.setModuleNamespace(moduleNamespace);

            // Empty-named root namespace hosting symbols imported from other modules (see importRootNamespace).
            // Owned by the module symbol (like the module namespace) so it is treated as a module-root when
            // collecting namespace paths (collectSymbolMapNamespacePath) and contributes no name prefix.
            auto* importRootNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), namespaceFlags);
            importRootNamespace->setOwnerSymMap(symModule);
            compiler.setImportRootNamespace(importRootNamespace);
        }

        for (SourceFile* f : files)
        {
            f->setModuleNamespace(*moduleNamespace);
            auto* job = compiler.makeJob<SemaJob>(ctx, f->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        {
            SWC_SCHED_PHASE(jobMgr, "sema declarations");
            jobMgr.waitAll(clientId);
        }

        {
            SWC_SCHED_PHASE(jobMgr, "sema");
            for (SourceFile* f : files)
            {
                auto* job = compiler.makeJob<SemaJob>(ctx, f->nodePayloadContext(), false);
                jobMgr.enqueue(*job, JobPriority::Normal, clientId);
            }

            Sema::waitDone(ctx, clientId);
        }

        if (compiler.validateAllocatorConfig(ctx) == Result::Error)
            return;

        if (isEditorServiceCommand(compiler.cmdLine().command))
        {
            for (SourceFile* f : files)
                compiler.updateEditorDependencies(*f);
        }

        {
            SWC_SCHED_PHASE(jobMgr, "api export");
            if (!files.empty() && !Stats::hasError() && CompilerInstance::exportModuleApi(ctx) == Result::Error)
                return;
        }

        if (stage)
        {
            const ScopedTimedLog::StatsSnapshot deltaSnapshot = stage->delta();
            std::vector<Utf8>                   statParts;
            if (deltaSnapshot.numFiles)
                statParts.push_back(ScopedTimedLog::formatStatCount(ctx, deltaSnapshot.numFiles, "file"));
            if (deltaSnapshot.numTokens)
                statParts.push_back(ScopedTimedLog::formatStatCount(ctx, deltaSnapshot.numTokens, "token"));

            stage->setStat(ScopedTimedLog::joinStatItems(ctx, statParts));
        }
    }
}

SWC_END_NAMESPACE();
