#pragma once

class DiagReporter;

class CompilerInstance
{
    std::unique_ptr<DiagReporter> diagReporter_;

public:
    CompilerInstance();
    [[nodiscard]] std::unique_ptr<DiagReporter>& diagReporter() { return diagReporter_; }
};
