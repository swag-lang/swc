#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeRDataCollector;
class NativeStartupBuildJob;

struct NativeArtifactPaths
{
    Utf8                  name;
    Utf8                  artifactExtension;
    fs::path              workDir;
    fs::path              buildDir;
    fs::path              outDir;
    fs::path              artifactPath;
    fs::path              pdbPath;
    std::vector<fs::path> objectPaths;
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

    Result          clearOutputFolders(const NativeArtifactPaths& paths) const;
    Utf8            artifactName() const;
    Utf8            artifactExtension() const;
    Utf8            objectExtension() const;
    fs::path        configuredOutDir(const fs::path& defaultOutDir) const;
    Result          createOutDir(const fs::path& outDir) const;
    fs::path        configuredWorkDir() const;
    Utf8            automaticWorkDirName(const Utf8& name) const;
    static fs::path buildDir(const fs::path& workDir);
    Result          createBuildDir(const fs::path& buildDir) const;

    Result prepareDataSections() const;
    Result buildStartupAndDataSectionsParallel() const;
    void   resetDataSections() const;
    Result prepareDataSectionsWithoutStartup(NativeRDataCollector& rdataCollector) const;
    Result finishDataSections(NativeRDataCollector& rdataCollector) const;
    Result resolveFunctionRelocationName(Utf8& outName, const SymbolFunction* targetFunction) const;
    Result partitionObjects() const;
    Result buildStartup(TaskContext& ctx) const;

    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();
