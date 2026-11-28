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
    namespace
    {
        bool markPublicNamespaces(SymbolNamespace& root)
        {
            if (root.isPrivate())
                return false;

            std::vector<const Symbol*> symbols;
            root.getAllSymbols(symbols);
            bool hasPublic = false;
            for (const Symbol* symbol : symbols)
            {
                if (const auto* child = symbol->safeCast<SymbolNamespace>())
                    hasPublic |= markPublicNamespaces(*const_cast<SymbolNamespace*>(child));
                else
                    hasPublic |= symbol->isPublic();
            }

            if (hasPublic)
                root.addFlag(SymbolFlagsE::Public);
            return hasPublic;
        }
    }

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

        // Parser
        const uint64_t         errorsBefore  = Stats::getNumErrors();
        const ParserJobOptions parserOptions = {
            .emitTrivia = compiler.cmdLine().command == CommandKind::Doc,
        };
        {
            SWC_SCHED_PHASE(jobMgr, "parse");
            parseSourceFiles(ctx, inputFiles, parserOptions);
        }
        if (Stats::getNumErrors() != errorsBefore)
            return;

        // Filter files
        std::vector<SourceFile*> files;
        files.reserve(inputFiles.size());
        for (SourceFile* f : inputFiles)
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
        moduleAsts.reserve(files.size());
        for (SourceFile* f : files)
            moduleAsts.push_back(&f->ast());
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

        compiler.assignSourceNamespaces(ctx, files);
        compiler.prepareSemaBodyCache(files);
        const auto semaFiles = [&](const std::span<SourceFile* const> group) {
            {
                SWC_SCHED_PHASE(jobMgr, "sema declarations");
                for (SourceFile* file : group)
                {
                    auto* job = compiler.makeJob<SemaJob>(ctx, file->nodePayloadContext(), true);
                    jobMgr.enqueue(*job, JobPriority::Normal, clientId);
                }
                jobMgr.waitAll(clientId);
            }

            {
                SWC_SCHED_PHASE(jobMgr, "sema");
                for (SourceFile* file : group)
                {
                    auto* job = compiler.makeJob<SemaJob>(ctx, file->nodePayloadContext(), false);
                    jobMgr.enqueue(*job, JobPriority::Normal, clientId);
                }
                Sema::waitDone(ctx, clientId);
            }
        };

        if (!compiler.hasSourceDependencies())
        {
            semaFiles(files);
        }
        else
        {
            std::vector<SourceFile*> runtimeFiles;
            std::map<uint32_t, std::vector<SourceFile*>> sourceGroups;
            for (SourceFile* file : files)
            {
                if (file->isRuntime())
                    runtimeFiles.push_back(file);
                else
                    sourceGroups[file->sourceOwner()].push_back(file);
            }

            semaFiles(runtimeFiles);
            if (Stats::getNumErrors() != errorsBefore)
                return;

            SmallVector<const SymbolMap*> prelude;
            moduleNamespace->copyUsingSymMaps(prelude);
            auto application = sourceGroups.extract(0);
            for (const auto& [owner, group] : sourceGroups)
            {
                auto* ns = const_cast<SymbolNamespace*>(group.front()->moduleNamespace());
                for (const SymbolMap* usingMap : prelude)
                    ns->addUsingSymMap(ctx, const_cast<SymbolMap*>(usingMap));
                compiler.beginSourceSemanticPass(owner);
                semaFiles(group);
                if (Stats::getNumErrors() != errorsBefore)
                    return;
                markPublicNamespaces(*ns);
            }

            compiler.beginSourceSemanticPass(0);
            if (!application.empty())
                semaFiles(application.mapped());
        }

        if (compiler.validateAllocatorConfig(ctx) == Result::Error)
            return;

        if (compiler.cmdLine().command == CommandKind::Doc)
        {
            SWC_SCHED_PHASE(jobMgr, "documentation symbols");
            if (!files.empty() && !Stats::hasError() && CompilerInstance::collectDocumentation(ctx) == Result::Error)
                return;
        }

        if (stage)
        {
            const ScopedTimedLog::StatsSnapshot deltaSnapshot = stage->delta();
            std::vector<Utf8>                   statParts;
            if (deltaSnapshot.numFiles)
                statParts.push_back(ScopedTimedLog::formatStatCount(deltaSnapshot.numFiles, "file"));
            if (deltaSnapshot.numTokens)
                statParts.push_back(ScopedTimedLog::formatStatCount(deltaSnapshot.numTokens, "token"));
            if (deltaSnapshot.numDeferredFunctionBodies)
                statParts.push_back(ScopedTimedLog::formatStatCount(deltaSnapshot.numDeferredFunctionBodies, "deferred function body", "deferred function bodies"));

            stage->setStat(ScopedTimedLog::joinStatItems(statParts));
        }
    }
}

SWC_END_NAMESPACE();
