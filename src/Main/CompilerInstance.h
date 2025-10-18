#pragma once

struct DiagReporter;

struct CompilerInstance
{
    CompilerInstance();

private:
    std::unique_ptr<DiagReporter> diagReporter_;
};
