#pragma once

class Logger;
class Reporter;

class CompilerInstance
{
    std::unique_ptr<Reporter> diagReporter_;
    std::unique_ptr<Logger>       logger_;

public:
    CompilerInstance();
    [[nodiscard]] Reporter& diagReporter() const { return *diagReporter_; }
    [[nodiscard]] Logger&       logger() const { return *logger_; }
};
