#pragma once

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }
    void log(std::string message);

private:
    std::mutex mutexAccess_;
};
