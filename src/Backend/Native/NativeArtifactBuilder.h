#pragma once
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class NativeRDataCollector;
class NativeStartupBuildJob;
class NativeBackendBuilder;
class TaskContext;

struct NativeArtifactPaths
{
    Utf8 name;
    Utf8 artifactExtension;

    fs::path workDir;
    fs::path buildDir;
    fs::path outDir;
    fs::path artifactPath;
    fs::path pdbPath;

    // The static archive a shared library publishes beside its DLL, from the same objects. Empty
    // unless the build was asked for one through CommandLine::staticLibraryOutDir.
    fs::path staticLibraryPath;

    std::vector<fs::path> objectPaths;

    // How the stage reports name the artifact: its file name, or the whole path when it has none.
    Utf8 artifactLabel() const { return artifactPath.filename().empty() ? Utf8(artifactPath) : Utf8(artifactPath.filename()); }
};

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    Result build() const;
    Result prepareOutputFolders() const;
    void   queryPaths(NativeArtifactPaths& outPaths, uint32_t numObjects = 0) const;

private:
    friend class NativeStartupBuildJob;

    Utf8   artifactExtension() const;
    Utf8   objectExtension() const;
    Result createDirectories(const fs::path& path) const;
    Utf8   automaticWorkDirName(const Utf8& name) const;

    Result prepareDataSections() const;
    Result buildStartupAndDataSectionsParallel() const;
    void   resetDataSections() const;
    Result prepareDataSectionsWithoutStartup(NativeRDataCollector& rdataCollector) const;
    Result finishDataSections(NativeRDataCollector& rdataCollector) const;
    Result partitionObjects() const;

public:
    // Partition lowered code into one-function members so archive extraction
    // retains only the requested functions. Object 0 owns writable data; read-only
    // allocations use transitively linked members, batched to fit the 16-bit directory.
    //
    // Lowering must be complete: partitioning overwrites its text offsets.
    Result partitionArchiveObjects() const;
    Result partitionIncrementalObject() const;
    Result partitionIncrementalFunctionObjects() const;

private:
    Result buildRuntimeHook(TaskContext& ctx) const;
    Result buildStartup(TaskContext& ctx) const;

    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();
