#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Os/ProcessOutput.h"

#ifdef __linux__
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
// Some glibc pidfd headers omit C++ linkage guards around their C declarations.
extern "C"
{
#include <sys/pidfd.h>
}
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ProcessResult
    {
        Os::ProcessRunResult result = Os::ProcessRunResult::StartFailed;
        uint32_t            exitCode = 0;
        int                 error = 0;
    };

    void closeDescriptor(int& descriptor)
    {
        if (descriptor >= 0)
            close(descriptor);
        descriptor = -1;
    }

    bool makePipe(int (&descriptors)[2])
    {
        if (pipe2(descriptors, O_CLOEXEC) != 0)
            return false;
        // Preserve intentionally closed standard streams when arranging child descriptors.
        for (int& descriptor : descriptors)
        {
            if (descriptor >= 3)
                continue;
            const int moved = fcntl(descriptor, F_DUPFD_CLOEXEC, 3);
            if (moved < 0)
                return false;
            close(descriptor);
            descriptor = moved;
        }
        return true;
    }

    struct ProcessHandles
    {
        int   control[2] = {-1, -1};
        int   status[2] = {-1, -1};
        int   output[2] = {-1, -1};
        int   parent = -1;
        pid_t supervisor = -1;

        ~ProcessHandles()
        {
            const int savedError = errno;
            // Closing this end asks the supervisor to cancel, including during C++ unwinding.
            closeDescriptor(control[1]);
            if (supervisor > 0)
            {
                int statusValue;
                while (waitpid(supervisor, &statusValue, 0) < 0 && errno == EINTR)
                {
                }
            }
            for (int& descriptor : control)
                closeDescriptor(descriptor);
            for (int& descriptor : status)
                closeDescriptor(descriptor);
            for (int& descriptor : output)
                closeDescriptor(descriptor);
            closeDescriptor(parent);
            errno = savedError;
        }
    };

    struct ProcessArguments
    {
        std::string              executable;
        std::string              directory;
        std::vector<std::string> arguments;
        std::vector<std::string> environment;
        std::vector<char*>       argv;
        std::vector<char*>       envp;
    };

    bool prepareProcess(ProcessArguments& out, const fs::path& executable, const std::span<const Utf8> args, const fs::path& directory, const Os::ProcessRunOptions* options)
    {
        if (executable.empty() || executable.native().find('\0') != std::string::npos || directory.native().find('\0') != std::string::npos)
        {
            errno = EINVAL;
            return false;
        }
        std::error_code error;
        const fs::path workingDirectory = directory.empty() ? fs::current_path(error) : fs::absolute(directory, error);
        if (error)
        {
            errno = error.value();
            return false;
        }
        out.directory = workingDirectory.string();
        out.arguments.push_back(executable.string());
        for (const auto& arg : args)
        {
            if (arg.find('\0') != Utf8::npos)
            {
                errno = EINVAL;
                return false;
            }
            out.arguments.push_back(arg);
        }
        for (const auto& arg : out.arguments)
            out.argv.push_back(const_cast<char*>(arg.c_str()));
        out.argv.push_back(nullptr);

        std::string searchPath;
        if (options)
        {
            for (const auto& path : options->additionalPathDirectories)
            {
                if (path.empty())
                    continue;
                const auto text = path.string();
                if (text.find('\0') != std::string::npos || text.find(':') != std::string::npos)
                {
                    errno = EINVAL;
                    return false;
                }
                searchPath += text;
                searchPath += ':';
            }
        }
        const char* inheritedPath = std::getenv("PATH");
        searchPath += inheritedPath ? inheritedPath : "/bin:/usr/bin";
        for (char** entry = environ; entry && *entry; ++entry)
        {
            if (!std::string_view(*entry).starts_with("PATH="))
                out.environment.emplace_back(*entry);
        }
        out.environment.emplace_back("PATH=" + searchPath);
        for (const auto& entry : out.environment)
            out.envp.push_back(const_cast<char*>(entry.c_str()));
        out.envp.push_back(nullptr);

        if (executable.has_parent_path())
            out.executable = (executable.is_absolute() ? executable : workingDirectory / executable).string();
        else
        {
            size_t start = 0;
            bool denied = false;
            while (true)
            {
                const size_t end = searchPath.find(':', start);
                const fs::path candidate = workingDirectory / searchPath.substr(start, end == std::string::npos ? end : end - start) / executable;
                if (access(candidate.c_str(), X_OK) == 0 && fs::is_regular_file(candidate, error))
                {
                    out.executable = candidate.string();
                    break;
                }
                denied |= errno == EACCES;
                if (end == std::string::npos)
                {
                    errno = denied ? EACCES : ENOENT;
                    return false;
                }
                start = end + 1;
            }
        }
        return true;
    }

    // Everything below that runs after fork uses fixed storage and native calls only. The
    // compiler can fork while other threads own allocator, iostream or loader locks.
    bool closeOtherDescriptors(int* keep, const size_t count)
    {
        for (size_t i = 0; i < count; ++i)
        {
            for (size_t j = i + 1; j < count; ++j)
            {
                if (keep[j] < keep[i])
                {
                    const int value = keep[i];
                    keep[i] = keep[j];
                    keep[j] = value;
                }
            }
        }
        unsigned int first = 3;
        for (size_t i = 0; i < count; ++i)
        {
            if (keep[i] < 3)
                continue;
            const auto descriptor = static_cast<unsigned int>(keep[i]);
            if (first < descriptor && close_range(first, descriptor - 1, 0) != 0)
                return false;
            first = descriptor + 1;
        }
        return close_range(first, std::numeric_limits<unsigned int>::max(), 0) == 0;
    }

    uint64_t monotonicMilliseconds()
    {
        timespec now{};
        clock_gettime(CLOCK_MONOTONIC, &now);
        return static_cast<uint64_t>(now.tv_sec) * 1000 + static_cast<uint64_t>(now.tv_nsec) / 1000000;
    }

    void killAdoptedChildren(const int procDirectory)
    {
        if (lseek(procDirectory, 0, SEEK_SET) < 0)
            return;
        const pid_t supervisor = getpid();
        alignas(dirent64) char entries[8192];
        ssize_t length;
        while ((length = getdents64(procDirectory, entries, sizeof(entries))) > 0)
        {
            for (size_t offset = 0; offset < static_cast<size_t>(length);)
            {
                const auto* entry = reinterpret_cast<const dirent64*>(entries + offset);
                offset += entry->d_reclen;
                if (entry->d_name[0] < '0' || entry->d_name[0] > '9')
                    continue;
                pid_t pid = 0;
                for (const char* digit = entry->d_name; *digit >= '0' && *digit <= '9'; ++digit)
                    pid = pid * 10 + *digit - '0';
                const int directory = openat(procDirectory, entry->d_name, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
                if (directory < 0)
                    continue;
                const int stat = openat(directory, "stat", O_RDONLY | O_CLOEXEC);
                close(directory);
                if (stat < 0)
                    continue;
                char data[1024];
                const ssize_t size = read(stat, data, sizeof(data));
                close(stat);
                // comm can contain spaces and parentheses. The final ')' precedes state/ppid.
                ssize_t end = size - 1;
                while (end >= 0 && data[end] != ')')
                    --end;
                if (end < 0 || end + 4 >= size)
                    continue;
                pid_t parent = 0;
                for (ssize_t i = end + 4; i < size && data[i] >= '0' && data[i] <= '9'; ++i)
                    parent = parent * 10 + data[i] - '0';
                // No child is reaped between this identity check and kill, so an adopted
                // child's PID cannot be recycled into an unrelated process here.
                if (parent == supervisor)
                    kill(pid, SIGKILL);
            }
        }
    }

    void terminateDescendants(const pid_t command, const int procDirectory)
    {
        // The command remains unreaped until after killpg, so its process-group ID cannot
        // be recycled. Subreaping then catches descendants that called setsid/setpgid.
        kill(-command, SIGKILL);
        kill(command, SIGKILL);
        while (true)
        {
            int status;
            pid_t child;
            do
                child = waitpid(-1, &status, WNOHANG);
            while (child > 0 || (child < 0 && errno == EINTR));
            if (child < 0 && errno == ECHILD)
                return;

            killAdoptedChildren(procDirectory);
            poll(nullptr, 0, 2);
        }
    }

    [[noreturn]] void executeCommand(const ProcessArguments& args, const ProcessHandles& handles, const int errorPipe, const pid_t supervisor)
    {
        bool ready = setpgid(0, 0) == 0 && prctl(PR_SET_PDEATHSIG, SIGKILL) == 0;
        if (ready && getppid() != supervisor)
        {
            errno = ECANCELED;
            ready = false;
        }
        if (ready && handles.output[1] >= 0)
            ready = dup2(handles.output[1], STDOUT_FILENO) >= 0 && dup2(handles.output[1], STDERR_FILENO) >= 0;
        int keep[]{errorPipe};
        ready = ready && closeOtherDescriptors(keep, 1) && chdir(args.directory.c_str()) == 0;
        if (ready)
            execve(args.executable.c_str(), args.argv.data(), args.envp.data());
        const int error = errno;
        (void) write(errorPipe, &error, sizeof(error));
        _exit(127);
    }

    [[noreturn]] void supervise(const ProcessArguments& args, ProcessHandles& handles, const uint32_t timeout)
    {
        ProcessResult result;
        int keep[]{handles.control[0], handles.status[1], handles.parent, handles.output[1]};
        bool ready = closeOtherDescriptors(keep, 4) && setsid() >= 0 && prctl(PR_SET_CHILD_SUBREAPER, 1) == 0;
        struct sigaction action{};
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        ready = ready && sigaction(SIGCHLD, &action, nullptr) == 0;
        int execError[2] = {-1, -1};
        const int procDirectory = ready ? open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC) : -1;
        ready = ready && procDirectory >= 0;
        ready = ready && pipe2(execError, O_CLOEXEC | O_NONBLOCK) == 0;
        const pid_t supervisor = getpid();
        const pid_t command = ready ? fork() : -1;
        if (command == 0)
            executeCommand(args, handles, execError[1], supervisor);
        if (command < 0)
            result.error = errno;
        closeDescriptor(execError[1]);
        closeDescriptor(handles.output[1]);

        // The supervisor is outside the compiler's terminal session and follows a pidfd
        // as well as the cancellation pipe, so SIGKILL of the compiler cannot orphan a tree.
        action.sa_handler = SIG_IGN;
        sigaction(SIGPIPE, &action, nullptr);
        if (command > 0)
        {
            const uint64_t deadline = timeout ? monotonicMilliseconds() + timeout : 0;
            while (true)
            {
                pollfd watched[]{{handles.control[0], POLLIN, 0}, {handles.parent, POLLIN, 0}, {execError[0], POLLIN, 0}};
                const int polled = poll(watched, 3, 10);
                if (polled < 0 && errno == EINTR)
                    continue;
                if (polled < 0)
                {
                    result.result = Os::ProcessRunResult::WaitFailed;
                    result.error = errno;
                    break;
                }
                if (watched[0].revents || watched[1].revents)
                {
                    result.result = Os::ProcessRunResult::WaitFailed;
                    result.error = ECANCELED;
                    break;
                }
                if (execError[0] >= 0)
                {
                    int error = 0;
                    const ssize_t received = read(execError[0], &error, sizeof(error));
                    if (received == sizeof(error))
                    {
                        result.error = error;
                        break;
                    }
                    if (received == 0)
                        closeDescriptor(execError[0]);
                    else if (received < 0 && errno != EINTR && errno != EAGAIN)
                    {
                        result.result = Os::ProcessRunResult::WaitFailed;
                        result.error = errno;
                        break;
                    }
                }

                siginfo_t status{};
                if (waitid(P_PID, static_cast<id_t>(command), &status, WEXITED | WNOHANG | WNOWAIT) != 0)
                {
                    if (errno == EINTR)
                        continue;
                    result.result = Os::ProcessRunResult::WaitFailed;
                    result.error = errno;
                    break;
                }
                if (status.si_pid && execError[0] < 0)
                {
                    result.result = Os::ProcessRunResult::Ok;
                    result.exitCode = status.si_code == CLD_EXITED ? static_cast<uint32_t>(status.si_status) : 128u + static_cast<uint32_t>(status.si_status);
                    break;
                }
                if (deadline && monotonicMilliseconds() >= deadline)
                {
                    result.result = Os::ProcessRunResult::TimedOut;
                    break;
                }
            }
            terminateDescendants(command, procDirectory);
        }
        closeDescriptor(execError[0]);
        (void) write(handles.status[1], &result, sizeof(result));
        _exit(0);
    }
}

Utf8 Os::formatProcessCommandLine(const fs::path& executable, const std::span<const Utf8> args)
{
    // Display/copy syntax only: execve always receives the unmodified argument vector.
    Utf8 result;
    const auto append = [&](const std::string_view value) {
        result += '\'';
        for (const char ch : value)
        {
            if (ch == '\'')
                result += "'\\''";
            else
                result += ch;
        }
        result += '\'';
    };
    append(executable.string());
    for (const auto& arg : args)
    {
        result += ' ';
        append(arg);
    }
    return result;
}

Os::ProcessRunResult Os::runProcess(uint32_t& outExitCode, const fs::path& executable, const std::span<const Utf8> args, const fs::path& workingDirectory, const ProcessRunOptions* options)
{
    outExitCode = 0;
    ProcessArguments arguments;
    if (!prepareProcess(arguments, executable, args, workingDirectory, options))
        return ProcessRunResult::StartFailed;
    ProcessOutput output(options);
    ProcessHandles handles;
    handles.parent = pidfd_open(getpid(), 0);
    if (handles.parent < 0 || !makePipe(handles.control) || !makePipe(handles.status) || (output.needsPipe() && !makePipe(handles.output)))
        return ProcessRunResult::StartFailed;
    handles.supervisor = fork();
    if (handles.supervisor < 0)
        return ProcessRunResult::StartFailed;
    if (handles.supervisor == 0)
        supervise(arguments, handles, options ? options->timeoutMs : 0);
    closeDescriptor(handles.control[0]);
    closeDescriptor(handles.status[1]);
    closeDescriptor(handles.output[1]);
    closeDescriptor(handles.parent);

    ProcessResult result;
    bool receivedStatus = false;
    while (!receivedStatus || handles.output[0] >= 0)
    {
        pollfd watched[]{{handles.status[0], POLLIN, 0}, {handles.output[0], POLLIN, 0}};
        const int polled = poll(watched, 2, -1);
        if (polled < 0)
        {
            if (errno == EINTR)
                continue;
            return ProcessRunResult::WaitFailed;
        }
        if (watched[1].revents)
        {
            char buffer[16384];
            const ssize_t count = read(handles.output[0], buffer, sizeof(buffer));
            if (count > 0)
                output.append(std::string_view(buffer, static_cast<size_t>(count)));
            else if (count == 0)
                closeDescriptor(handles.output[0]);
            else if (errno != EINTR)
                return ProcessRunResult::WaitFailed;
        }
        if (watched[0].revents)
        {
            ssize_t count;
            do
                count = read(handles.status[0], &result, sizeof(result));
            while (count < 0 && errno == EINTR);
            if (count != sizeof(result))
                return ProcessRunResult::WaitFailed;
            receivedStatus = true;
            closeDescriptor(handles.status[0]);
        }
    }
    output.flush();
    outExitCode = result.exitCode;
    if (result.error)
        errno = result.error;
    return result.result;
}

SWC_END_NAMESPACE();
#endif
