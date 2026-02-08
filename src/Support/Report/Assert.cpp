#include "pch.h"
#include <cstdio>
#include <cstdlib>
#include "Main/TaskContext.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void logInternalError(const TaskContext* ctx, const char* message, const char* file, int line)
    {
        std::string msg = "internal error: ";
        msg += message;
        msg += " (";
        msg += file;
        msg += ":";
        msg += std::to_string(line);
        msg += ")\n";

        if (ctx)
        {
            auto& logger = ctx->global().logger();
            logger.lock();
            Logger::print(*ctx, msg);
            logger.unlock();
        }
        else
        {
            std::fwrite(msg.data(), sizeof(char), msg.size(), stderr);
            std::fflush(stderr);
        }
    }
}

void swagAssert(const char* expr, const char* file, int line)
{
    Os::assertBox(expr, file, line);
}

[[noreturn]] void swagInternalError(const char* message, const char* file, int line)
{
    logInternalError(nullptr, message, file, line);
    const std::string msg = std::string(message) + " (" + file + ":" + std::to_string(line) + ")";
    Os::panicBox(msg.c_str());
    std::abort();
}

[[noreturn]] void swagInternalError(const TaskContext& ctx, const char* message, const char* file, int line)
{
    logInternalError(&ctx, message, file, line);
    const std::string msg = std::string(message) + " (" + file + ":" + std::to_string(line) + ")";
    Os::panicBox(msg.c_str());
    std::abort();
}

SWC_END_NAMESPACE();
