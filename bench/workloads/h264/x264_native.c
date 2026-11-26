#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/mem.h>

static void check(int result)
{
    if (result >= 0)
        return;
    char error[AV_ERROR_MAX_STRING_SIZE];
    fprintf(stderr, "%s\n", av_make_error_string(error, sizeof(error), result));
    exit(1);
}

static int number(const char *text, int minimum, int maximum)
{
    char *end;
    errno = 0;
    long result = strtol(text, &end, 10);
    if (errno || end == text || *end || result < minimum || result > maximum)
    {
        fprintf(stderr, "invalid numeric argument: %s\n", text);
        exit(2);
    }
    return (int)result;
}

static uint64_t ticks(clockid_t clock)
{
    struct timespec time;
    if (clock_gettime(clock, &time))
        abort();
    return (uint64_t)time.tv_sec * 1000000000 + time.tv_nsec;
}

static void read_plane(FILE *input, uint8_t *plane, int stride, int width, int rows)
{
    for (int row = 0; row < rows; ++row)
    {
        if (fread(plane, 1, width, input) != (size_t)width)
            check(AVERROR_INVALIDDATA);
        plane += stride;
    }
}

static AVFrame **load_frames(const char *path, AVCodecContext *codec, int count)
{
    FILE *input = fopen(path, "rb");
    if (!input)
        check(AVERROR(errno));
    AVFrame **frames = av_calloc(count, sizeof(*frames));
    if (!frames)
        check(AVERROR(ENOMEM));
    for (int index = 0; index < count; ++index)
    {
        AVFrame *frame = av_frame_alloc();
        if (!frame)
            check(AVERROR(ENOMEM));
        frame->format = codec->pix_fmt;
        frame->width = codec->width;
        frame->height = codec->height;
        frame->pts = index;
        frame->color_range = codec->color_range;
        frame->color_primaries = codec->color_primaries;
        frame->color_trc = codec->color_trc;
        frame->colorspace = codec->colorspace;
        check(av_frame_get_buffer(frame, 32));
        read_plane(input, frame->data[0], frame->linesize[0], frame->width, frame->height);
        read_plane(input, frame->data[1], frame->linesize[1], frame->width, frame->height / 2);
        frames[index] = frame;
    }
    if (fgetc(input) != EOF || ferror(input))
        check(AVERROR_INVALIDDATA);
    fclose(input);
    return frames;
}

static void receive(AVCodecContext *codec, AVPacket **packets, int capacity,
                    int *count, uint64_t *bytes, AVPacket *packet)
{
    for (;;)
    {
        int result = avcodec_receive_packet(codec, packet);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF)
            return;
        check(result);
        if (*count == capacity)
            check(AVERROR_INVALIDDATA);
        *bytes += packet->size;
        av_packet_move_ref(packets[(*count)++], packet);
    }
}

int main(int argc, char **argv)
{
    if (argc != 12 || (strcmp(argv[10], "qp") && strcmp(argv[10], "crf")))
    {
        fprintf(stderr, "usage: x264_native input.nv12 output.mp4 width height frames threads slices preset profile qp|crf quality\n");
        return 2;
    }
    const int width = number(argv[3], 2, INT_MAX);
    const int height = number(argv[4], 2, INT_MAX);
    const int frames_count = number(argv[5], 1, INT_MAX);
    const int threads = number(argv[6], 1, INT_MAX);
    const int slices = number(argv[7], 1, INT_MAX);
    number(argv[11], 0, 51);
    if (width % 2 || height % 2)
        return 2;

    const AVCodec *encoder = avcodec_find_encoder_by_name("libx264");
    if (!encoder)
        check(AVERROR_ENCODER_NOT_FOUND);
    AVCodecContext *codec = avcodec_alloc_context3(encoder);
    if (!codec)
        check(AVERROR(ENOMEM));

    codec->width = width;
    codec->height = height;
    codec->pix_fmt = AV_PIX_FMT_NV12;
    codec->time_base = (AVRational){1, 30};
    codec->framerate = (AVRational){30, 1};
    codec->gop_size = 120;
    codec->thread_count = threads;
    codec->color_range = AVCOL_RANGE_MPEG;
    codec->color_primaries = AVCOL_PRI_BT709;
    codec->color_trc = AVCOL_TRC_BT709;
    codec->colorspace = AVCOL_SPC_BT709;
    codec->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    AVDictionary *options = NULL;
    char params[64];
    snprintf(params, sizeof(params), "scenecut=0:slices=%d", slices);
    check(av_dict_set(&options, "preset", argv[8], 0));
    check(av_dict_set(&options, "profile", argv[9], 0));
    check(av_dict_set(&options, argv[10], argv[11], 0));
    check(av_dict_set(&options, "x264-params", params, 0));
    check(avcodec_open2(codec, encoder, &options));
    if (av_dict_count(options))
        check(AVERROR_OPTION_NOT_FOUND);
    av_dict_free(&options);

    AVFrame **frames = load_frames(argv[1], codec, frames_count);
    AVPacket *packet = av_packet_alloc();
    AVPacket **packets = av_calloc(frames_count, sizeof(*packets));
    if (!packet || !packets)
        check(AVERROR(ENOMEM));
    for (int index = 0; index < frames_count; ++index)
    {
        packets[index] = av_packet_alloc();
        if (!packets[index])
            check(AVERROR(ENOMEM));
    }

    int count = 0;
    uint64_t bytes = 0;
    const uint64_t wall_start = ticks(CLOCK_MONOTONIC);
    const uint64_t cpu_start = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (int index = 0; index < frames_count; ++index)
    {
        check(avcodec_send_frame(codec, frames[index]));
        receive(codec, packets, frames_count, &count, &bytes, packet);
    }
    check(avcodec_send_frame(codec, NULL));
    receive(codec, packets, frames_count, &count, &bytes, packet);
    const uint64_t cpu_elapsed = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const uint64_t wall_elapsed = ticks(CLOCK_MONOTONIC) - wall_start;
    if (count != frames_count)
        check(AVERROR_INVALIDDATA);

    AVFormatContext *container = NULL;
    check(avformat_alloc_output_context2(&container, NULL, "mp4", argv[2]));
    AVStream *stream = avformat_new_stream(container, NULL);
    if (!stream)
        check(AVERROR(ENOMEM));
    stream->time_base = codec->time_base;
    stream->avg_frame_rate = codec->framerate;
    check(avcodec_parameters_from_context(stream->codecpar, codec));
    check(avio_open(&container->pb, argv[2], AVIO_FLAG_WRITE));
    check(avformat_write_header(container, NULL));
    for (int index = 0; index < count; ++index)
    {
        packets[index]->stream_index = stream->index;
        av_packet_rescale_ts(packets[index], codec->time_base, stream->time_base);
        check(av_interleaved_write_frame(container, packets[index]));
        av_packet_free(&packets[index]);
        av_frame_free(&frames[index]);
    }
    check(av_write_trailer(container));
    check(avio_closep(&container->pb));
    avformat_free_context(container);
    avcodec_free_context(&codec);
    av_packet_free(&packet);
    av_free(packets);
    av_free(frames);
    printf("H264 frames=%d us=%" PRIu64 " cpu_us=%" PRIu64 " bytes=%" PRIu64 "\n",
           count, wall_elapsed / 1000, cpu_elapsed / 1000, bytes);
}
