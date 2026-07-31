#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view HELLO_SOURCE = R"(#main
{
    @print("Hello, world!\n")
}
)";

    constexpr std::string_view MODULE_SOURCE = R"(#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.backendKind = .Executable
}
)";

    Result reportPathError(TaskContext& ctx, const DiagnosticId id, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(id);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result reportPathExists(TaskContext& ctx, const fs::path& path)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_new_target_exists);
        FileSystem::setDiagnosticPath(diag, &ctx, path);
        diag.report(ctx);
        return Result::Error;
    }

    Result ensureTargetDoesNotExist(TaskContext& ctx, const fs::path& path)
    {
        std::error_code ec;
        if (fs::exists(path, ec))
            return reportPathExists(ctx, path);
        if (ec)
            return reportPathError(ctx, DiagnosticId::cmd_err_new_target_check_failed, path, FileSystem::normalizeSystemMessage(ec));
        return Result::Continue;
    }

    Result createDirectories(TaskContext& ctx, const fs::path& path)
    {
        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
            return reportPathError(ctx, DiagnosticId::cmd_err_new_directory_create_failed, path, FileSystem::normalizeSystemMessage(ec));
        return Result::Continue;
    }

    Result writeStarterFile(TaskContext& ctx, const fs::path& path, const std::string_view content)
    {
        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFile(path, content.data(), content.size(), error) != Result::Continue)
            return reportPathError(ctx, DiagnosticId::cmd_err_new_file_write_failed, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    fs::path displayPath(const fs::path& path)
    {
        std::error_code ec;
        const fs::path  currentDir = fs::current_path(ec);
        if (ec)
            return path;

        const fs::path relative = fs::relative(path, currentDir, ec);
        if (ec || relative.empty())
            return path;
        return relative;
    }

    Utf8 quoteCommandArgument(const fs::path& path)
    {
        Utf8 value{displayPath(path).string()};
        if (value.find_first_of(" \t\"") == Utf8::npos)
            return value;

        Utf8 result = "\"";
        result += value;
        result += "\"";
        return result;
    }

    void printCreatedScript(const TaskContext& ctx, const fs::path& scriptPath)
    {
        using CommandPrint::addInfoEntry;

        const Utf8 scriptArg = quoteCommandArgument(scriptPath);
        std::vector<Logger::FieldEntry> entries;
        addInfoEntry(entries, "Script", displayPath(scriptPath), LogColor::BrightGreen);
        addInfoEntry(entries, "Run", "swc " + scriptArg, LogColor::White, 0, CommandPrint::helpArgumentLabelColor());
        addInfoEntry(entries, "Learn", "swc help", LogColor::White, 0, CommandPrint::helpArgumentLabelColor());

        Logger::FieldGroupStyle style = CommandPrint::infoGroupStyle(true, 18);
        Logger::printFieldGroup(ctx, "Created", entries, style);
    }

    void printCreatedModule(const TaskContext& ctx, const fs::path& workspacePath, const fs::path& modulePath, const Utf8& moduleName)
    {
        using CommandPrint::addInfoEntry;

        const Utf8 workspaceArg = quoteCommandArgument(workspacePath);
        std::vector<Logger::FieldEntry> entries;
        addInfoEntry(entries, "Workspace", displayPath(workspacePath), LogColor::BrightGreen);
        addInfoEntry(entries, "Module", displayPath(modulePath), LogColor::BrightGreen);
        addInfoEntry(entries, "Run", "swc run --workspace " + workspaceArg + " --workspace-module " + moduleName, LogColor::White, 0, CommandPrint::helpArgumentLabelColor());
        addInfoEntry(entries, "Learn", "swc help", LogColor::White, 0, CommandPrint::helpArgumentLabelColor());

        Logger::FieldGroupStyle style = CommandPrint::infoGroupStyle(true, 18);
        Logger::printFieldGroup(ctx, "Created", entries, style);
    }

    bool isModuleName(const TaskContext& ctx, const Utf8& name)
    {
        if (name.empty())
            return false;

        const LangSpec& langSpec = ctx.global().langSpec();
        if (!langSpec.isIdentifierStart(static_cast<uint8_t>(name[0])))
            return false;

        for (size_t i = 1; i < name.size(); i++)
        {
            if (!langSpec.isIdentifierPart(static_cast<uint8_t>(name[i])))
                return false;
        }

        return true;
    }

    Result createScript(TaskContext& ctx)
    {
        fs::path scriptPath = ctx.cmdLine().newScriptPath.empty() ? fs::path("hello.swgs") : ctx.cmdLine().newScriptPath;
        if (scriptPath.extension().empty())
            scriptPath += ".swgs";

        std::string extension = scriptPath.extension().string();
        std::ranges::transform(extension, extension.begin(), [](const char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c; });
        if (extension != ".swgs")
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_new_script_extension);
            FileSystem::setDiagnosticPath(diag, &ctx, scriptPath);
            diag.report(ctx);
            return Result::Error;
        }

        scriptPath = FileSystem::normalizePath(scriptPath);
        SWC_RESULT(ensureTargetDoesNotExist(ctx, scriptPath));

        const fs::path parentPath = scriptPath.parent_path();
        if (!parentPath.empty())
            SWC_RESULT(createDirectories(ctx, parentPath));

        SWC_RESULT(writeStarterFile(ctx, scriptPath, HELLO_SOURCE));
        printCreatedScript(ctx, scriptPath);
        return Result::Continue;
    }

    Result createModule(TaskContext& ctx)
    {
        const Utf8& moduleName = ctx.cmdLine().newProjectName;
        if (!isModuleName(ctx, moduleName))
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_new_module_name_invalid);
            diag.addArgument(Diagnostic::ARG_VALUE, moduleName);
            diag.report(ctx);
            return Result::Error;
        }

        const fs::path workspacePath = FileSystem::normalizePath(ctx.cmdLine().workspacePath.empty() ? fs::path(moduleName.c_str()) : ctx.cmdLine().workspacePath);
        const fs::path modulePath    = workspacePath / "modules" / moduleName.c_str();
        const fs::path sourcePath    = modulePath / "src";
        SWC_RESULT(ensureTargetDoesNotExist(ctx, modulePath));
        SWC_RESULT(createDirectories(ctx, sourcePath));

        if (writeStarterFile(ctx, modulePath / "module.swg", MODULE_SOURCE) != Result::Continue ||
            writeStarterFile(ctx, sourcePath / "main.swg", HELLO_SOURCE) != Result::Continue)
        {
            std::error_code ec;
            fs::remove_all(modulePath, ec);
            return Result::Error;
        }

        printCreatedModule(ctx, workspacePath, modulePath, moduleName);
        return Result::Continue;
    }
}

namespace Command
{
    Result createProject(TaskContext& ctx)
    {
        switch (ctx.cmdLine().newProjectKind)
        {
            case NewProjectKind::Script:
                return createScript(ctx);
            case NewProjectKind::Module:
                return createModule(ctx);
            case NewProjectKind::Invalid:
                SWC_UNREACHABLE();
        }

        SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
