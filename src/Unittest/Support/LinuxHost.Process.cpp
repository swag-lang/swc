#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Os/ProcessOutput.h"
#include "Unittest/Support/LinuxHostTests.h"
#include <fcntl.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc::LinuxHostTests
{
    namespace
    {
        struct Lines
        {
            mutable std::vector<std::string> values;

            static void observe(void* data, const std::string_view line)
            {
                static_cast<Lines*>(data)->values.emplace_back(line);
            }

            static void forward(const void* data, const std::string_view line)
            {
                static_cast<const Lines*>(data)->values.emplace_back(line);
            }
        };

        struct ChildTree
        {
            pid_t command = 0;
            pid_t descendant = 0;
            pid_t supervisor = 0;
        };

        ChildTree readTree(const fs::path& path)
        {
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
            while (std::chrono::steady_clock::now() < deadline)
            {
                ChildTree tree;
                std::ifstream file(path);
                if (file >> tree.command >> tree.descendant >> tree.supervisor)
                    return tree;
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            throw std::runtime_error("child tree did not publish its identities");
        }

        void requireTreeGone(const ChildTree& tree)
        {
            require(tree.command > 0 && tree.descendant > 0, "child tree has no identities");
            require(kill(tree.command, 0) < 0 && errno == ESRCH, "direct child survived process completion");
            require(kill(tree.descendant, 0) < 0 && errno == ESRCH, "detached descendant survived process completion");
        }

        void checkCallerDeath()
        {
            // Adopt the supervisor so this test can reap it after killing its calling process.
            int previous = 0;
            require(prctl(PR_GET_CHILD_SUBREAPER, &previous) == 0 && prctl(PR_SET_CHILD_SUBREAPER, 1) == 0, "cannot supervise caller-death test");
            const fs::path marker = fs::absolute("caller-death.txt");
            const pid_t runner = fork();
            if (runner == 0)
            {
                uint32_t exitCode;
                const Os::ProcessRunOptions options{.forwardOutput = false, .timeoutMs = 10000};
                const std::array<Utf8, 3> args{"--host-child", "tree", marker.string()};
                Os::runProcess(exitCode, Os::getExeFullName(), args, {}, &options);
                _exit(1);
            }
            require(runner > 0, "cannot create process caller");
            const ChildTree tree = readTree(marker);
            require(kill(runner, SIGKILL) == 0, "cannot stop process caller");
            const int runnerStatus = waitForChild(runner);
            require(WIFSIGNALED(runnerStatus) && WTERMSIG(runnerStatus) == SIGKILL, "caller did not stop with SIGKILL");
            const int supervisorStatus = waitForChild(tree.supervisor);
            require(WIFEXITED(supervisorStatus), "supervisor did not complete cleanup");
            requireTreeGone(tree);
            require(prctl(PR_SET_CHILD_SUBREAPER, previous) == 0, "cannot restore subreaper setting");
        }
    }

    int runProcessChild(const int argc, char* argv[])
    {
        if (argc < 3 || std::string_view(argv[1]) != "--host-child")
            return 2;
        const std::string_view mode = argv[2];
        if (mode == "echo")
        {
            for (int i = 3; i < argc; ++i)
                std::cout << std::strlen(argv[i]) << ':' << argv[i] << '\n';
            return 0;
        }
        if (mode == "context")
        {
            std::cout << fs::current_path().string() << '\n' << std::getenv("PATH") << '\n';
            return 0;
        }
        if (mode == "exit")
            return argc == 4 ? std::atoi(argv[3]) : 2;
        if (mode == "signal")
        {
            raise(SIGTERM);
            return 2;
        }
        if (mode == "descriptor")
            return argc == 4 && fcntl(std::atoi(argv[3]), F_GETFD) < 0 && errno == EBADF ? 0 : 2;
        if (mode == "lines")
        {
            constexpr std::string_view first = "first\r\n[marker] secret\n";
            write(STDOUT_FILENO, first.data(), first.size());
            write(STDERR_FILENO, "last", 4);
            return 0;
        }
        if (mode == "noisy")
        {
            const std::string output(4096, 'x');
            while (true)
                write(STDOUT_FILENO, output.data(), output.size());
        }
        if ((mode == "tree" || mode == "tree-exit") && argc == 4)
        {
            int ready[2];
            if (pipe2(ready, O_CLOEXEC) != 0)
                return 2;
            const pid_t descendant = fork();
            if (descendant < 0)
                return 2;
            if (descendant == 0)
            {
                close(ready[0]);
                if (setsid() < 0 || write(ready[1], "x", 1) != 1)
                    _exit(2);
                close(ready[1]);
                for (;;)
                    pause();
            }
            close(ready[1]);
            char byte;
            if (read(ready[0], &byte, 1) != 1)
                return 2;
            close(ready[0]);
            std::ofstream marker(argv[3]);
            marker << getpid() << ' ' << descendant << ' ' << getppid();
            marker.close();
            std::cout << "tree ready\n" << std::flush;
            if (mode == "tree-exit")
                return 0;
        }
        else if (mode != "quiet")
            return 2;
        for (;;)
            pause();
    }

    void testProcessOutput()
    {
        Lines observed;
        Lines forwarded;
        std::string captured;
        Os::ProcessRunOptions options{
            .capturedOutput = &captured,
            .forwardLineCallback = &Lines::forward,
            .forwardLineUserData = &forwarded,
            .outputLineCallback = &Lines::observe,
            .outputLineUserData = &observed,
            .suppressForwardLinePrefix = "[marker]",
        };
        Os::ProcessOutput output(&options);
        require(output.needsPipe(), "line capture did not request a pipe");
        output.append("fi");
        output.append("rst\r\n[mar");
        output.append("ker] secret\nlast");
        output.flush();
        require(captured == "first\r\n[marker] secret\nlast", "chunk capture changed bytes");
        require(observed.values == std::vector<std::string>{"first\r\n", "[marker] secret\n", "last"}, "chunk boundaries changed observed lines");
        require(forwarded.values == std::vector<std::string>{"first\r\n", "last"}, "suppression changed forwarded lines");
        options.forwardOutput = false;
        output.append("hidden\n");
        require(observed.values.back() == "hidden\n" && forwarded.values.size() == 2, "muted forwarding suppressed the observer");
    }

    void testProcessServices()
    {
        uint32_t exitCode = 0;
        const fs::path executable = Os::getExeFullName();
        std::string captured;
        Os::ProcessRunOptions options{.capturedOutput = &captured, .forwardOutput = false, .timeoutMs = 3000};
        const std::array<Utf8, 8> args{"--host-child", "echo", "", "two words", "quote'\"", "slash\\", "line\nbreak", "\xc3\xa9"};
        const auto argumentResult = Os::runProcess(exitCode, executable, args, {}, &options);
        require(argumentResult == Os::ProcessRunResult::Ok && !exitCode, std::format("argument-vector child failed: result {}, exit {}, errno {}", static_cast<int>(argumentResult), exitCode, errno).c_str());
        std::string expected;
        for (size_t i = 2; i < args.size(); ++i)
            expected += std::to_string(args[i].size()) + ':' + args[i] + '\n';
        require(captured == expected, "process quoting changed arguments");
        require(Os::formatProcessCommandLine("a b", std::array<Utf8, 2>{"", "x'y"}) == "'a b' '' 'x'\\''y'", "process display quoting differs");

        Lines observed;
        Lines forwarded;
        const Os::ProcessRunOptions streamOptions{
            .capturedOutput = &captured,
            .forwardLineCallback = &Lines::forward,
            .forwardLineUserData = &forwarded,
            .outputLineCallback = &Lines::observe,
            .outputLineUserData = &observed,
            .suppressForwardLinePrefix = "[marker]",
            .timeoutMs = 3000,
        };
        const std::array<Utf8, 2> lineArgs{"--host-child", "lines"};
        captured.clear();
        require(Os::runProcess(exitCode, executable, lineArgs, {}, &streamOptions) == Os::ProcessRunResult::Ok && !exitCode, "line-output child failed");
        require(captured == "first\r\n[marker] secret\nlast" && observed.values == std::vector<std::string>{"first\r\n", "[marker] secret\n", "last"}, "process pipe lost output or its final partial line");
        require(forwarded.values == std::vector<std::string>{"first\r\n", "last"}, "process pipe forwarding ignored suppression");

        for (const int code : {0, 7, 127})
        {
            const std::array<Utf8, 3> exitArgs{"--host-child", "exit", std::to_string(code)};
            require(Os::runProcess(exitCode, executable, exitArgs, {}, &options) == Os::ProcessRunResult::Ok && exitCode == static_cast<uint32_t>(code), "process exit status differs");
        }
        const std::array<Utf8, 2> echoArgs{"--host-child", "echo"};
        require(Os::runProcess(exitCode, "/swc-missing-program", echoArgs, {}, &options) == Os::ProcessRunResult::StartFailed && errno == ENOENT, "missing executable was not a startup failure");
        require(Os::runProcess(exitCode, executable, echoArgs, "missing-working-directory", &options) == Os::ProcessRunResult::StartFailed && errno == ENOENT, "missing working directory was not a startup failure");
        const std::array<Utf8, 1> invalidArgs{Utf8("x\0y", 3)};
        require(Os::runProcess(exitCode, executable, invalidArgs, {}, &options) == Os::ProcessRunResult::StartFailed && errno == EINVAL, "process accepted an embedded NUL");
        const std::array<Utf8, 2> signalArgs{"--host-child", "signal"};
        require(Os::runProcess(exitCode, executable, signalArgs, {}, &options) == Os::ProcessRunResult::Ok && exitCode == 128 + SIGTERM, "signal exit status differs");

        fs::create_directory("process working directory");
        fs::create_directory("process search path");
        fs::create_symlink(executable, "process search path/host-child");
        const std::array<fs::path, 1> search{fs::absolute("process search path")};
        const std::string parentPath = std::getenv("PATH");
        options.additionalPathDirectories = search;
        const std::array<Utf8, 2> contextArgs{"--host-child", "context"};
        captured.clear();
        require(Os::runProcess(exitCode, "host-child", contextArgs, "process working directory", &options) == Os::ProcessRunResult::Ok && !exitCode, "PATH/working-directory child failed");
        require(captured == fs::absolute("process working directory").string() + '\n' + search[0].string() + ':' + parentPath + '\n', "child environment or working directory differs");
        require(std::string_view(std::getenv("PATH")) == parentPath, "process launch changed the caller environment");
        options.additionalPathDirectories = {};

        const int descriptor = open("descriptor-fixture", O_CREAT | O_RDWR, 0600);
        require(descriptor >= 0, "cannot open inherited-descriptor fixture");
        const std::array<Utf8, 3> descriptorArgs{"--host-child", "descriptor", std::to_string(descriptor)};
        const auto descriptorResult = Os::runProcess(exitCode, executable, descriptorArgs, {}, &options);
        close(descriptor);
        require(descriptorResult == Os::ProcessRunResult::Ok && !exitCode, "process inherited an unrelated descriptor");

        options.timeoutMs = 40;
        for (const char* mode : {"quiet", "noisy"})
        {
            captured.clear();
            const std::array<Utf8, 2> timeoutArgs{"--host-child", mode};
            require(Os::runProcess(exitCode, executable, timeoutArgs, {}, &options) == Os::ProcessRunResult::TimedOut, "process deadline did not cover output pumping");
        }
        options.timeoutMs = 3000;
        const fs::path treeMarker = fs::absolute("completed-tree.txt");
        const std::array<Utf8, 3> treeArgs{"--host-child", "tree-exit", treeMarker.string()};
        require(Os::runProcess(exitCode, executable, treeArgs, {}, &options) == Os::ProcessRunResult::Ok && !exitCode, "tree-exit child failed");
        requireTreeGone(readTree(treeMarker));
        checkCallerDeath();

        const fs::path unwindMarker = fs::absolute("unwound-tree.txt");
        const std::array<Utf8, 3> unwindArgs{"--host-child", "tree", unwindMarker.string()};
        const Os::ProcessRunOptions unwindOptions{
            .forwardOutput = false,
            .outputLineCallback = [](void*, std::string_view) { throw std::runtime_error("stop process observer"); },
            .timeoutMs = 3000,
        };
        bool observerThrew = false;
        try
        {
            Os::runProcess(exitCode, executable, unwindArgs, {}, &unwindOptions);
        }
        catch (const std::runtime_error& error)
        {
            observerThrew = std::string_view(error.what()) == "stop process observer";
        }
        require(observerThrew, "process observer exception was swallowed");
        requireTreeGone(readTree(unwindMarker));

        std::atomic<bool> parallelOk = true;
        std::array<std::jthread, 3> workers;
        for (auto& worker : workers)
        {
            worker = std::jthread([&] {
                uint32_t code;
                const Os::ProcessRunOptions localOptions{.forwardOutput = false, .timeoutMs = 3000};
                for (size_t i = 0; i < 3; ++i)
                {
                    if (Os::runProcess(code, executable, echoArgs, {}, &localOptions) != Os::ProcessRunResult::Ok || code)
                        parallelOk = false;
                }
            });
        }
        for (auto& worker : workers)
            worker.join();
        require(parallelOk, "concurrent process launches interfered");
    }
}
