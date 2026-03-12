#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

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
    void   queryPaths(NativeArtifactPaths& outPaths, std::optional<uint32_t> workDirIndex = std::nullopt, uint32_t numObjects = 0) const;

private:
    Result          prepareDataSections() const;
    Result          buildStartup() const;
    Result          partitionObjects() const;
    Result          clearOutputFolders(const NativeArtifactPaths& paths) const;
    Utf8            artifactName() const;
    Utf8            artifactExtension() const;
    Utf8            objectExtension() const;
    fs::path        configuredOutDir(const fs::path& defaultOutDir) const;
    Result          createOutDir(const fs::path& outDir) const;
    fs::path        configuredWorkDir() const;
    Utf8            automaticWorkDirName(const Utf8& name) const;
    static fs::path buildDir(const fs::path& workDir, uint32_t buildIndex);
    Result          createBuildDir(const fs::path& buildDir) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
