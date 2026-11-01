#include "pch.h"
#include "Support/Os/ProcessOutput.h"

SWC_BEGIN_NAMESPACE();

Utf8 Os::formatProcessExitCode(const uint32_t exitCode)
{
    return std::format("{} (0x{:08X})", exitCode, exitCode);
}

bool Os::ProcessOutput::needsPipe() const
{
    return options_ && (options_->capturedOutput || !options_->forwardOutput || options_->outputLineCallback || options_->forwardLineCallback || !options_->suppressForwardLinePrefix.empty());
}

void Os::ProcessOutput::emit(const std::string_view line) const
{
    if (options_ && options_->outputLineCallback)
        options_->outputLineCallback(options_->outputLineUserData, line);
    if (options_ && (!options_->forwardOutput || (!options_->suppressForwardLinePrefix.empty() && line.starts_with(options_->suppressForwardLinePrefix))))
        return;
    if (options_ && options_->forwardLineCallback)
        options_->forwardLineCallback(options_->forwardLineUserData, line);
    else
    {
        std::fwrite(line.data(), 1, line.size(), stdout);
        std::fflush(stdout);
    }
}

void Os::ProcessOutput::append(const std::string_view bytes)
{
    if (options_ && options_->capturedOutput)
        options_->capturedOutput->append(bytes);
    if (options_ && !options_->forwardOutput && !options_->outputLineCallback)
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
