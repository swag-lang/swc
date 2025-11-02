#pragma once

SWC_BEGIN_NAMESPACE()

enum class LogColor;
class Context;

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }

    static void print(const Context& ctx, std::string_view message);
    static void printDim(const Context& ctx, std::string_view message);
    static void printHeaderDot(const Context& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 40);
    static void printHeaderCentered(const Context& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn = 24);

private:
    std::mutex mutexAccess_;
};

SWC_END_NAMESPACE()
