#pragma once

class Logger;
class DiagnosticIds;
class LangSpec;
class JobManager;
class FileManager;

class Global
{
    std::unique_ptr<DiagnosticIds> diagIds_;
    std::unique_ptr<Logger>        logger_;
    std::unique_ptr<LangSpec>      langSpec_;
    std::unique_ptr<JobManager>    jobManager_;
    std::unique_ptr<FileManager>   fileManager_;

public:
    void initialize();

    static Global& get();

    const DiagnosticIds& diagIds() const { return *diagIds_; }
    Logger&              logger() const { return *logger_; }
    LangSpec&            langSpec() const { return *langSpec_; }
    JobManager&          jobMgr() const { return *jobManager_; }
    FileManager&         fileMgr() const { return *fileManager_; }
};
