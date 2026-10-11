#include "pch.h"
#include "Main/EditorService.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/EditorIndex.h"
#include "Main/Global.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view EDITOR_SERVICE_PREFIX = "SWAG-EDITOR-SERVICE\t1\t";

    std::optional<std::string> editorModuleConfiguration(const CommandLine& cmdLine)
    {
        fs::path moduleFilePath = cmdLine.moduleFilePath;
        if (moduleFilePath.empty() && !cmdLine.modulePath.empty())
            moduleFilePath = cmdLine.modulePath / "module.swg";
        if (moduleFilePath.empty())
            return std::nullopt;

        if (cmdLine.editorSources)
        {
            const auto it = cmdLine.editorSources->find(EditorIndex::pathKey(moduleFilePath));
            if (it != cmdLine.editorSources->end())
                return it->second;
        }

        std::ifstream input(moduleFilePath, std::ios::binary);
        if (!input)
            return std::nullopt;
        return std::string(std::istreambuf_iterator<char>(input), {});
    }
}

ExitCode runEditorService(Global& global, CommandLine& cmdLine)
{
    std::println(stdout, "{}READY", EDITOR_SERVICE_PREFIX);
    std::println(stderr, "{}READY", EDITOR_SERVICE_PREFIX);
    (void) std::fflush(stdout);
    (void) std::fflush(stderr);

    std::string request;
    std::unique_ptr<CompilerInstance> compiler;
    std::optional<std::string> moduleConfiguration;
    bool hasModuleConfigurationSnapshot = false;
    while (std::getline(std::cin, request))
    {
        if (request == "shutdown")
            return ExitCode::Success;

        constexpr std::string_view ANALYZE_PREFIX = "analyze\t";
        const std::string_view requestView(request);
        const std::string_view idText = requestView.starts_with(ANALYZE_PREFIX) ? requestView.substr(ANALYZE_PREFIX.size()) : std::string_view{};
        uint64_t                requestId = 0;
        const auto              parsedId  = std::from_chars(idText.data(), idText.data() + idText.size(), requestId);
        ExitCode                result    = ExitCode::ErrorCmdLine;
        if (!idText.empty() && parsedId.ec == std::errc{} && parsedId.ptr == idText.data() + idText.size())
        {
            result = ExitCode::ErrorCommand;
            if (EditorIndex::loadOverlays(cmdLine) == Result::Continue)
            {
                std::optional<std::string> nextModuleConfiguration = editorModuleConfiguration(cmdLine);
                if (hasModuleConfigurationSnapshot && moduleConfiguration != nextModuleConfiguration)
                    compiler.reset();
                moduleConfiguration = std::move(nextModuleConfiguration);
                hasModuleConfigurationSnapshot = true;

                if (!compiler)
                    compiler = std::make_unique<CompilerInstance>(global, cmdLine);
                result = compiler->run();
                if (EditorIndex::write(*compiler) != Result::Continue)
                    result = ExitCode::ErrorCommand;
            }
        }

        std::cout.flush();
        std::cerr.flush();
        (void) std::fflush(stdout);
        (void) std::fflush(stderr);
        std::println(stdout, "{}{}\t{}", EDITOR_SERVICE_PREFIX, requestId, static_cast<int>(result));
        std::println(stderr, "{}{}\t{}", EDITOR_SERVICE_PREFIX, requestId, static_cast<int>(result));
        (void) std::fflush(stdout);
        (void) std::fflush(stderr);
    }

    return ExitCode::Success;
}

SWC_END_NAMESPACE();
