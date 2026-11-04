#include "pch.h"
#include "Main/ExitCodes.h"
#include "Support/Os/Os.h"

#ifdef __linux__
#include <sys/ioctl.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    std::once_flag   g_terminalInitialization;
    std::atomic_bool g_cursorHidden = false;

    bool supportsAnsi(const int descriptor)
    {
        const char* term = std::getenv("TERM");
        return isatty(descriptor) && term && *term && std::string_view(term) != "dumb";
    }

    void restoreCursor()
    {
        if (g_cursorHidden.exchange(false, std::memory_order_acq_rel))
        {
            std::fputs("\x1b[?25h", stdout);
            std::fflush(stdout);
        }
    }
}

void Os::initialize()
{
    std::call_once(g_terminalInitialization, [] { std::atexit(restoreCursor); });
}

bool Os::stdoutSupportsAnsi()
{
    return supportsAnsi(STDOUT_FILENO);
}

bool Os::stderrSupportsAnsi()
{
    return supportsAnsi(STDERR_FILENO);
}

bool Os::stdoutSupportsAnimation()
{
    return stdoutSupportsAnsi();
}

uint32_t Os::stdoutColumnCount()
{
    winsize size{};
    return ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 ? size.ws_col : 0;
}

void Os::setStdoutCursorVisible(const bool visible)
{
    initialize();
    if (!stdoutSupportsAnimation())
        return;
    g_cursorHidden.store(!visible, std::memory_order_release);
    std::fputs(visible ? "\x1b[?25h" : "\x1b[?25l", stdout);
    std::fflush(stdout);
}

void Os::panicBox(const std::string_view expr)
{
    std::println(stderr, "panic: {}", expr.empty() ? "<null>" : expr);
    Os::exit(ExitCode::PanicBox);
}

SWC_END_NAMESPACE();
#endif
