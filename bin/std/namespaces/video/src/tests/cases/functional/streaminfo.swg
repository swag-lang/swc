#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Picture codec names come from the decoded stream, while the source size includes its container.
#test
{
    func check(fileName, codec: string)
    {
        var reader = expect Reader.open(videoFixturePath(fileName), pictureOnly: true)
        Swag.require(reader.streamInfo().codecName == codec, fileName)
        Swag.require(reader.sourceSizeBytes() > 0, fileName)
    }

    check("ffmpeg-h264-baseline.mp4", "H.264 / AVC")
    check("ffmpeg-hevc-main.mp4", "H.265 / HEVC")
    check("ffmpeg-mjpeg.mp4", "Motion JPEG")
    check("ffmpeg-h264-two-aac.mkv", "H.264 / AVC")
    check("ffmpeg-hevc-main.mkv", "H.265 / HEVC")
    check("ffmpeg-mpeg4-bvop.mkv", "MPEG-4 Part 2")
    check("ffmpeg-mjpeg-ntsc.avi", "Motion JPEG")
    check("ffmpeg-mpeg4-packed.avi", "MPEG-4 Part 2")
    check("ffmpeg-rawvideo-bgr24.avi", "Uncompressed RGB")
    check("ffmpeg-ntsc-c420.y4m", "Uncompressed YUV")
}
