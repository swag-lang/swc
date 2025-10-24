#pragma once

SWC_BEGIN_NAMESPACE()

enum class LogColor;
class CompilerContext;

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }
    static void print(const CompilerContext& ctx, std::string_view message);
    static void printEol(const CompilerContext& ctx);
    void printHeaderDot(const CompilerContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 40);

private:
    std::mutex mutexAccess_;
};

SWC_END_NAMESPACE()
