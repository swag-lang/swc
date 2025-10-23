#pragma once

enum class Color;
class CompilerContext;

class Logger
{
public:
    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }
    void print(std::string_view message);
    void printEol();
    void printHeaderDot(Color headerColor, std::string_view header, Color msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 40);

private:
    std::mutex mutexAccess_;
};
