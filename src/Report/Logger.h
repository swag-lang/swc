#pragma once

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }
    void log(Utf8 message);
    void logEol();

private:
    std::mutex mutexAccess_;
};
