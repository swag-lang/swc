#include "pch.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/EditorIndex.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Memory/Allocator.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"
#if SWC_HAS_UNITTEST
#include "Unittest/Unittest.h"
#endif

namespace
{
    // A hosted run — a script, a JIT test — arms its sandbox inside this very process, so its
    // default root carries this process id, and the runtime's own drop hook leaves it in place:
    // the same process may host another run right after, and that run expects the armed root to
    // still be there. Once the command is over nothing hosted remains, which makes this the one
    // point that can retire the root. The name is the contract with the runtime sandbox in
    // bin/std/modules/core/src/system/sandbox.swg, and only this process's own directory is ever
    // considered — never a sweep over its siblings.
    void removeOwnDefaultSandboxRoot()
    {
        std::error_code ec;
        const fs::path  root = swc::Os::getTemporaryPath() / "swag-sandbox" / std::format("run-{}", swc::Os::currentProcessId());
        fs::remove_all(root, ec);
    }

#ifdef _WIN32
    // ReSharper disable once CppParameterMayBeConstPtrOrRef
    LONG WINAPI reportUnhandledHostException(EXCEPTION_POINTERS* exceptionPointers)
    {
        static std::atomic_bool reported = false;
        const auto*             record   = exceptionPointers ? exceptionPointers->ExceptionRecord : nullptr;
        if (!record || !swc::Os::isFatalHostException(record->ExceptionCode))
            return EXCEPTION_CONTINUE_SEARCH;
        if (reported.exchange(true, std::memory_order_acq_rel))
            return EXCEPTION_CONTINUE_SEARCH;

        const swc::TaskContext* ctx = swc::TaskContext::current();
        const swc::Utf8         msg = swc::HardwareException::format(ctx, "fatal error: unhandled host hardware exception", exceptionPointers);
        std::print(stderr, "{}", msg.c_str());
        (void) std::fflush(stderr);
        return EXCEPTION_CONTINUE_SEARCH;
    }

#endif
}

namespace
{
    constexpr std::string_view EDITOR_SERVICE_PREFIX = "SWAG-EDITOR-SERVICE\t1\t";

    std::optional<std::string> editorModuleConfiguration(const swc::CommandLine& cmdLine)
    {
        fs::path moduleFilePath = cmdLine.moduleFilePath;
        if (moduleFilePath.empty() && !cmdLine.modulePath.empty())
            moduleFilePath = cmdLine.modulePath / "module.swg";
        if (moduleFilePath.empty())
            return std::nullopt;

        if (cmdLine.editorSources)
        {
            const auto it = cmdLine.editorSources->find(swc::EditorIndex::pathKey(moduleFilePath));
            if (it != cmdLine.editorSources->end())
                return it->second;
        }

        std::ifstream input(moduleFilePath, std::ios::binary);
        if (!input)
            return std::nullopt;
        return std::string(std::istreambuf_iterator<char>(input), {});
    }

    int runEditorService(swc::Global& global, swc::CommandLine& cmdLine)
    {
        std::println(stdout, "{}READY", EDITOR_SERVICE_PREFIX);
        std::println(stderr, "{}READY", EDITOR_SERVICE_PREFIX);
        (void) std::fflush(stdout);
        (void) std::fflush(stderr);

        std::string request;
        std::unique_ptr<swc::CompilerInstance> compiler;
        std::optional<std::string>             moduleConfiguration;
        bool                                   hasModuleConfigurationSnapshot = false;
        while (std::getline(std::cin, request))
        {
            if (request == "shutdown")
                return static_cast<int>(swc::ExitCode::Success);

            constexpr std::string_view ANALYZE_PREFIX = "analyze\t";
            const std::string_view requestView(request);
            const std::string_view idText = requestView.starts_with(ANALYZE_PREFIX) ? requestView.substr(ANALYZE_PREFIX.size()) : std::string_view{};
            uint64_t                requestId = 0;
            const auto              parsedId  = std::from_chars(idText.data(), idText.data() + idText.size(), requestId);
            int                     result    = static_cast<int>(swc::ExitCode::ErrorCmdLine);
            if (!idText.empty() && parsedId.ec == std::errc{} && parsedId.ptr == idText.data() + idText.size())
            {
                result = static_cast<int>(swc::ExitCode::ErrorCommand);
                if (swc::EditorIndex::loadOverlays(cmdLine) == swc::Result::Continue)
                {
                    std::optional<std::string> nextModuleConfiguration = editorModuleConfiguration(cmdLine);
                    if (hasModuleConfigurationSnapshot && moduleConfiguration != nextModuleConfiguration)
                        compiler.reset();
                    moduleConfiguration = std::move(nextModuleConfiguration);
                    hasModuleConfigurationSnapshot = true;

                    if (!compiler)
                        compiler = std::make_unique<swc::CompilerInstance>(global, cmdLine);
                    {
                        result = static_cast<int>(compiler->run());
                        if (swc::EditorIndex::write(*compiler) != swc::Result::Continue)
                            result = static_cast<int>(swc::ExitCode::ErrorCommand);
                    }
                }
            }

            std::cout.flush();
            std::cerr.flush();
            (void) std::fflush(stdout);
            (void) std::fflush(stderr);
            std::println(stdout, "{}{}\t{}", EDITOR_SERVICE_PREFIX, requestId, result);
            std::println(stderr, "{}{}\t{}", EDITOR_SERVICE_PREFIX, requestId, result);
            (void) std::fflush(stdout);
            (void) std::fflush(stderr);
        }

        return static_cast<int>(swc::ExitCode::Success);
    }
}

int main(int argc, char* argv[])
{
    swc::Allocator::configure();

#ifdef _WIN32
    swc::Os::reserveFaultHandlerStack();
    void* hostExceptionHandler = AddVectoredExceptionHandler(1, reportUnhandledHostException);
#endif

    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != swc::Result::Continue)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);
    if (cmdLine.helpPrinted)
        return static_cast<int>(swc::ExitCode::Success);

    global.initialize(cmdLine);
    swc::TaskContext            startupCtx(global, cmdLine);
    const swc::ScopedCommandLog commandLog(startupCtx);

    if (cmdLine.command == swc::CommandKind::New)
    {
        const swc::Result result = swc::Command::createProject(startupCtx);
        return static_cast<int>(result == swc::Result::Continue ? swc::ExitCode::Success : swc::ExitCode::ErrorCommand);
    }

    // Removing what a build wrote needs none of what a build needs: no inputs to collect, no
    // module setup to run, and nothing to schedule.
    if (cmdLine.command == swc::CommandKind::Clean)
    {
        const swc::Result result = swc::Command::clean(startupCtx);
        return static_cast<int>(result == swc::Result::Continue ? swc::ExitCode::Success : swc::ExitCode::ErrorCommand);
    }

#if SWC_HAS_UNITTEST
    if (cmdLine.command == swc::CommandKind::Unittest && !cmdLine.dryRun && !cmdLine.showConfig)
    {
        if (swc::Unittest::runAll(startupCtx) != swc::Result::Continue)
            return static_cast<int>(swc::ExitCode::ErrorCommand);
        return static_cast<int>(swc::ExitCode::Success);
    }
#endif

    if (!cmdLine.editorService && swc::EditorIndex::loadOverlays(cmdLine) != swc::Result::Continue)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);

    int result;
    if (cmdLine.editorService)
        result = runEditorService(global, cmdLine);
    else
    {
        swc::CompilerInstance compiler(global, cmdLine);
        result = static_cast<int>(compiler.run());
        if (!cmdLine.editorIndex.empty() && swc::EditorIndex::write(compiler) != swc::Result::Continue)
            result = static_cast<int>(swc::ExitCode::ErrorCommand);
    }
#if SWC_DEV_MODE
    if (cmdLine.devSchedStats)
        global.jobMgr().printStats(startupCtx);
#endif
    removeOwnDefaultSandboxRoot();
    std::cout.flush();
    std::cerr.flush();
    (void) std::fflush(stdout);
    (void) std::fflush(stderr);
#ifdef _WIN32
    if (hostExceptionHandler)
        RemoveVectoredExceptionHandler(hostExceptionHandler);
#endif
    return result;
}
