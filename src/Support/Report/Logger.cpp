#include "pch.h"
#include "Support/Report/Logger.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::mutex& stdErrMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    void appendField(Utf8& out, const Logger::FieldEntry& entry, const uint32_t baseIndent)
    {
        out.append(2 * (static_cast<size_t>(baseIndent) + entry.indentLevel), ' ');
        if (!entry.label.empty())
        {
            out += entry.label;
            out += ": ";
        }

        out += entry.value;
        out += "\n";
    }
}

void Logger::resetStageClaims()
{
    const ScopedLock lock(*this);
    claimedStageKeys_.clear();
}

bool Logger::claimStageOnce(const std::string_view key)
{
    const ScopedLock lock(*this);
    for (const Utf8& existingKey : claimedStageKeys_)
    {
        if (existingKey == key)
            return false;
    }

    claimedStageKeys_.emplace_back(key);
    return true;
}

void Logger::print(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    const ScopedLock lock(ctx.global().logger());
    std::cout << message;
}

void Logger::printStdErr(const std::string_view message)
{
    const std::scoped_lock lock(stdErrMutex());
    (void) std::fwrite(message.data(), sizeof(char), message.size(), stderr);
    (void) std::fflush(stderr);
}

void Logger::printField(const TaskContext& ctx, const FieldEntry& entry)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    Utf8 out;
    appendField(out, entry, 0);

    const ScopedLock lock(ctx.global().logger());
    std::cout << out;
}

void Logger::printFieldGroup(const TaskContext& ctx, const std::string_view title, const std::vector<FieldEntry>& entries)
{
    if (ctx.cmdLine().silent || ctx.muteOutput() || entries.empty())
        return;

    Utf8 out;
    if (!title.empty())
    {
        out += title;
        out += ":\n";
    }

    for (const FieldEntry& entry : entries)
        appendField(out, entry, title.empty() ? 0 : 1);

    const ScopedLock lock(ctx.global().logger());
    std::cout << out;
}

SWC_END_NAMESPACE();
