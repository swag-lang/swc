#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/SymbolSort.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/ExternalModuleManager.h"
#include "Main/Stats.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    namespace
    {
        Result finishNonArtifactBackend(CompilerInstance& compiler)
        {
            TaskContext outputCtx(compiler);
            return CommandRun::afterPauses(outputCtx, [&] { return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput); });
        }

        Result finishBuildBackend(CompilerInstance& compiler, const bool runArtifact)
        {
            const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
            compiler.buildCfg().backendKind                = backendKind;

            if (!Runtime::backendKindProducesNativeArtifact(backendKind))
                return finishNonArtifactBackend(compiler);

            const bool runExecutable = runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable;

            // Workspace pipeline: build everything but the link, then hand the prepared builder back so
            // the caller can run the linker off the main thread and finish it at a later sync point.
            // The builder owns its own TaskContext, so it only needs the compiler kept alive.
            if (compiler.deferNativeLink())
            {
                auto builder = std::make_unique<NativeBackendBuilder>(compiler, runExecutable);
                if (CommandRun::afterPauses(builder->ctx(), [&] { return builder->prepareForLink(); }) != Result::Continue)
                    return Result::Error;

                compiler.setDeferredBuilder(std::move(builder));
                return Result::Continue;
            }

            TaskContext          nativeCtx(compiler);
            NativeBackendBuilder builder(compiler, runExecutable);
            return CommandRun::afterPauses(nativeCtx, [&] { return builder.run(); });
        }

        enum class ScriptRuntimeHookStage : uint64_t
        {
            Init    = 1,
            PreMain = 2,
            Drop    = 3,
        };

        using RuntimeHookInvoker = void (*)(uint64_t, uint64_t, uint64_t);

        Result reportMissingRuntimeHook(TaskContext& ctx, const NativeRuntimeDependency& dependency, const Utf8& hookSymbolName)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_invalid_foreign_function_relocation);
            diag.addArgument(Diagnostic::ARG_SYM, hookSymbolName);
            diag.addNote(DiagnosticId::cmd_note_relocation_foreign_module_name);
            diag.last().addArgument(Diagnostic::ARG_VALUE, dependency.linkModuleName);
            diag.addNote(DiagnosticId::cmd_note_relocation_foreign_function_name);
            diag.last().addArgument(Diagnostic::ARG_TARGET, hookSymbolName);
            diag.addNote(DiagnosticId::cmd_note_relocation_foreign_lookup_failed);
            diag.report(ctx);
            return Result::Error;
        }

        Result runRuntimeDependencyHook(TaskContext& ctx, const NativeRuntimeDependency& dependency, const ScriptRuntimeHookStage stage)
        {
            const Utf8 hookSymbolName = runtimeHookSymbolName(dependency.linkModuleName.view());
            void*      hookAddress    = nullptr;
            if (!ctx.compiler().externalModuleMgr().getFunctionAddress(hookAddress, dependency.linkModuleName.view(), hookSymbolName.view()))
                return reportMissingRuntimeHook(ctx, dependency, hookSymbolName);

            const uint64_t tlsIdPlusOne = *CompilerInstance::runtimeContextTlsIdStorage() + 1;
            const auto     hookInvoker  = reinterpret_cast<RuntimeHookInvoker>(hookAddress);
            hookInvoker(static_cast<uint64_t>(stage), tlsIdPlusOne, static_cast<uint64_t>(Runtime::RuntimeFlags::Zero));
            return Result::Continue;
        }

        Result runRuntimeDependencyHooks(TaskContext& ctx, std::span<const NativeRuntimeDependency> dependencies, std::span<const uint32_t> order, const ScriptRuntimeHookStage stage)
        {
            for (const uint32_t dependencyIndex : order)
            {
                SWC_ASSERT(dependencyIndex < dependencies.size());
                if (dependencyIndex >= dependencies.size())
                    continue;

                SWC_RESULT(runRuntimeDependencyHook(ctx, dependencies[dependencyIndex], stage));
            }

            return Result::Continue;
        }

        SymbolFunction* runtimeFunction(CompilerInstance& compiler, const IdentifierManager::RuntimeFunctionKind kind)
        {
            const IdentifierRef idRef = compiler.idMgr().runtimeFunction(kind);
            return compiler.runtimeFunctionSymbol(idRef);
        }

        Result runJitScriptFunction(TaskContext& ctx, const SymbolFunction& function, const JITRuntimeSetupMode setupMode, const uint64_t* arg0 = nullptr)
        {
            if (!function.jitEntryAddress())
                return Result::Error;

            JITExecManager::Request request;
            request.function         = &function;
            request.nodeRef          = function.declNodeRef();
            request.codeRef          = function.decl() ? function.decl()->codeRef() : SourceCodeRef::invalid();
            request.runImmediate     = true;
            request.runtimeSetupMode = setupMode;
            if (arg0)
            {
                request.arg0    = *arg0;
                request.hasArg0 = true;
            }
            return CommandRun::afterPauses(ctx, [&] { return ctx.compiler().jitExecMgr().submit(ctx, request); });
        }

        Result runJitScriptFunctions(TaskContext& ctx, std::span<SymbolFunction* const> functions, const JITRuntimeSetupMode setupMode)
        {
            for (const SymbolFunction* function : functions)
            {
                if (!function)
                    continue;
                SWC_RESULT(runJitScriptFunction(ctx, *function, setupMode));
                if (Stats::hasError())
                    return Result::Error;
            }

            return Result::Continue;
        }

        Result runScriptRuntimeSetup(TaskContext& ctx)
        {
            SymbolFunction* setupFn = runtimeFunction(ctx.compiler(), IdentifierManager::RuntimeFunctionKind::SetupRuntime);
            SWC_ASSERT(setupFn != nullptr);
            if (!setupFn)
                return Result::Error;

            const uint64_t flags = static_cast<uint64_t>(Runtime::RuntimeFlags::Zero);
            return runJitScriptFunction(ctx, *setupFn, JITRuntimeSetupMode::None, &flags);
        }

        std::vector<SymbolFunction*> collectPreparedFunctions(const NativeBackendBuilder& builder)
        {
            std::vector<SymbolFunction*> result;
            result.reserve(builder.functionInfos.size());
            for (const NativeFunctionInfo& info : builder.functionInfos)
            {
                if (info.symbol)
                    result.push_back(info.symbol);
            }

            return result;
        }

        Result finishScriptBackend(CompilerInstance& compiler)
        {
            TaskContext ctx(compiler);
            TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::JIT);

            SWC_RESULT(CommandRun::afterPauses(ctx, [&] { return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeRunByteCode); }));

            std::vector<SymbolFunction*> allFunctions;
            std::vector<SymbolFunction*> initFunctions;
            std::vector<SymbolFunction*> preMainFunctions;
            std::vector<SymbolFunction*> mainFunctions;
            std::vector<SymbolFunction*> dropFunctions;
            std::vector<NativeRuntimeDependency> runtimeDependencies;
            std::vector<uint32_t>                runtimeDependencyInitOrder;
            std::vector<uint32_t>                runtimeDependencyDropOrder;
            {
                NativeBackendBuilder nativeBuilder(compiler, false);
                SWC_RESULT(nativeBuilder.prepare());
                allFunctions                = collectPreparedFunctions(nativeBuilder);
                initFunctions               = std::move(nativeBuilder.initFunctions);
                preMainFunctions            = std::move(nativeBuilder.preMainFunctions);
                mainFunctions               = std::move(nativeBuilder.mainFunctions);
                dropFunctions               = std::move(nativeBuilder.dropFunctions);
                runtimeDependencies         = std::move(nativeBuilder.runtimeDependencies);
                runtimeDependencyInitOrder  = std::move(nativeBuilder.runtimeDependencyInitOrder);
                runtimeDependencyDropOrder  = std::move(nativeBuilder.runtimeDependencyDropOrder);
            }

            SymbolSort::sortAndUniqueByLocation(allFunctions, compiler);
            SymbolSort::sortAndUniqueByLocation(initFunctions, compiler);
            SymbolSort::sortAndUniqueByLocation(preMainFunctions, compiler);
            SymbolSort::sortAndUniqueByLocation(mainFunctions, compiler);
            SymbolSort::sortAndUniqueByLocation(dropFunctions, compiler);

            SWC_RESULT(CommandRun::afterPauses(ctx, [&] { return SymbolFunction::jitBatch(ctx, allFunctions); }));

            SWC_RESULT(runScriptRuntimeSetup(ctx));
            SWC_RESULT(runRuntimeDependencyHooks(ctx, runtimeDependencies, runtimeDependencyInitOrder, ScriptRuntimeHookStage::Init));
            SWC_RESULT(runJitScriptFunctions(ctx, initFunctions, JITRuntimeSetupMode::None));
            SWC_RESULT(runRuntimeDependencyHooks(ctx, runtimeDependencies, runtimeDependencyInitOrder, ScriptRuntimeHookStage::PreMain));
            SWC_RESULT(runJitScriptFunctions(ctx, preMainFunctions, JITRuntimeSetupMode::None));
            SWC_RESULT(runJitScriptFunctions(ctx, mainFunctions, JITRuntimeSetupMode::None));
            SWC_RESULT(runJitScriptFunctions(ctx, dropFunctions, JITRuntimeSetupMode::None));
            SWC_RESULT(runRuntimeDependencyHooks(ctx, runtimeDependencies, runtimeDependencyDropOrder, ScriptRuntimeHookStage::Drop));

            stage.setStat(TimedActionLog::formatStatCount(ctx, mainFunctions.size(), "main"));
            return Result::Continue;
        }
    }

    void build(CompilerInstance& compiler)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (finishBuildBackend(compiler, false) != Result::Continue)
            return;
    }

    void run(CompilerInstance& compiler)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (compiler.cmdLine().scriptMode)
        {
            if (finishScriptBackend(compiler) != Result::Continue)
                return;
            return;
        }

        if (finishBuildBackend(compiler, true) != Result::Continue)
            return;
    }
}

SWC_END_NAMESPACE();
