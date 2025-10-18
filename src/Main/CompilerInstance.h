#pragma once

class Logger;
class DiagReporter;

class CompilerInstance
{
    std::unique_ptr<DiagReporter> diagReporter_;
    std::unique_ptr<Logger>       logger_;

public:
    CompilerInstance();
    [[nodiscard]] DiagReporter& diagReporter() const { return *diagReporter_; }
    [[nodiscard]] Logger&       logger() const { return *logger_; }
};
