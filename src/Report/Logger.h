#pragma once

class CompilerContext;

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }
    void log(const CompilerContext& ctx, std::string_view message);
    void logEol();

private:
    std::mutex mutexAccess_;
};
