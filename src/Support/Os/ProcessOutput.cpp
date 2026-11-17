#include "pch.h"
#include "Support/Os/ProcessOutput.h"

SWC_BEGIN_NAMESPACE();

Utf8 Os::formatProcessExitCode(const uint32_t exitCode)
{
    return std::format("{} (0x{:08X})", exitCode, exitCode);
}

bool Os::ProcessOutput::needsPipe() const
{
    if (!options_)
        return false;

    return options_->capturedOutput || !options_->forwardOutput || options_->outputLineCallback || options_->forwardLineCallback || !options_->suppressForwardLinePrefix.empty();
}

void Os::ProcessOutput::emit(const std::string_view line) const
{
    if (!options_)
    {
        std::fwrite(line.data(), 1, line.size(), stdout);
        std::fflush(stdout);
        return;
    }

    if (options_->outputLineCallback)
        options_->outputLineCallback(options_->outputLineUserData, line);
    if (!options_->forwardOutput || (!options_->suppressForwardLinePrefix.empty() && line.starts_with(options_->suppressForwardLinePrefix)))
        return;
    if (options_->forwardLineCallback)
    {
        options_->forwardLineCallback(options_->forwardLineUserData, line);
        return;
    }

    std::fwrite(line.data(), 1, line.size(), stdout);
    std::fflush(stdout);
}

void Os::ProcessOutput::append(const std::string_view bytes)
{
    const ProcessRunOptions* options = options_;
    if (options && options->capturedOutput)
        options->capturedOutput->append(bytes);
    if (options && !options->forwardOutput && !options->outputLineCallback)
        return;

    pendingLine_.append(bytes);
    size_t start = 0;
    while (true)
    {
        const size_t end = pendingLine_.find('\n', start);
        if (end == std::string::npos)
            break;
        emit(std::string_view(pendingLine_).substr(start, end - start + 1));
        start = end + 1;
    }
    pendingLine_.erase(0, start);
}

void Os::ProcessOutput::flush()
{
    if (pendingLine_.empty())
        return;
    emit(pendingLine_);
    pendingLine_.clear();
}

SWC_END_NAMESPACE();
