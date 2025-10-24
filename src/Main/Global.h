#pragma once

class Logger;
class DiagnosticIds;
class LangSpec;
class JobManager;
class FileManager;
struct CommandLine;

class Global
{
    DiagnosticIds* diagIds_     = nullptr;
    Logger*        logger_      = nullptr;
    LangSpec*      langSpec_    = nullptr;
    JobManager*    jobManager_  = nullptr;
    FileManager*   fileManager_ = nullptr;

public:
    void initialize(const CommandLine& cmdLine);

    const DiagnosticIds& diagIds() const { return *diagIds_; }
    Logger&              logger() const { return *logger_; }
    LangSpec&            langSpec() const { return *langSpec_; }
    JobManager&          jobMgr() const { return *jobManager_; }
    FileManager&         fileMgr() const { return *fileManager_; }
};
