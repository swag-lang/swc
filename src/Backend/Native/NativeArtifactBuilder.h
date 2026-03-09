#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

struct NativeArtifactPaths
{
    Utf8                  baseName;
    Utf8                  workDirRootName;
    Utf8                  artifactExtension;
    fs::path              workDirRoot;
    fs::path              workDir;
    fs::path              artifactOutputDir;
    fs::path              artifactPath;
    std::vector<fs::path> objectPaths;
};

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    Result build() const;
    void   queryPaths(NativeArtifactPaths& outPaths, std::optional<uint32_t> workDirIndex = std::nullopt, uint32_t numObjects = 0) const;

private:
    Result          validateNativeData() const;
    bool            isNativeStaticType(TypeRef typeRef) const;
    Result          validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
    bool            validateConstantRelocation(const MicroRelocation& relocation) const;
    bool            validateNativeStaticPayload(TypeRef typeRef, uint32_t shardIndex, Ref baseOffset, ByteSpan bytes) const;
    bool            findDataSegmentRelocation(uint32_t shardIndex, uint32_t offset, uint32_t& outTargetOffset) const;
    Result          prepareDataSections() const;
    Result          buildStartup() const;
    Result          partitionObjects() const;
    Utf8            configuredArtifactBaseName() const;
    Utf8            artifactBaseName() const;
    Utf8            artifactExtension() const;
    fs::path        configuredArtifactOutputDirectory(const fs::path& defaultOutputDir) const;
    Result          createArtifactOutputDirectory(const fs::path& outputDir) const;
    Utf8            configuredWorkDirectoryName() const;
    Utf8            automaticWorkDirectoryName(const Utf8& baseName) const;
    static fs::path workDirectory(const fs::path& workDirRoot, uint32_t workDirIndex);
    Result          createWorkDirectory(const fs::path& workDir) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
