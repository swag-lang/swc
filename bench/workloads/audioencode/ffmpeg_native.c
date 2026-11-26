#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>

static uint64_t micros(void)
{
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000000 + time.tv_nsec / 1000;
}

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

static void check(int result)
{
    if (result < 0) {
        char error[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(result, error, sizeof(error));
        require(0, error);
    }
}

static int number(const char *text, int minimum, int maximum)
{
    char *end;
    errno = 0;
    long value = strtol(text, &end, 10);
    require(!errno && *text && !*end && value >= minimum && value <= maximum, "Invalid numeric option");
    return (int)value;
}

static int16_t *read_pcm(const char *path, int channels, uint64_t *frames)
{
    FILE *file = fopen(path, "rb");
    require(file != NULL, "Cannot open PCM input");
    require(!fseeko(file, 0, SEEK_END), "Cannot seek PCM input");
    off_t size = ftello(file);
    require(size > 0 && (uintmax_t)size <= SIZE_MAX &&
            !(size % ((off_t)sizeof(int16_t) * channels)), "PCM input must contain whole frames");
    require(!fseeko(file, 0, SEEK_SET), "Cannot rewind PCM input");
    int16_t *samples = malloc((size_t)size);
    require(samples != NULL, "Cannot allocate PCM input");
    require(fread(samples, 1, (size_t)size, file) == (size_t)size, "Incomplete PCM input");
    require(!fclose(file), "Cannot close PCM input");
    *frames = (uint64_t)size / (sizeof(*samples) * channels);
    return samples;
}

static void drain(AVCodecContext *context, AVFormatContext *container, AVStream *stream, AVPacket *packet)
{
    for (;;) {
        int status = avcodec_receive_packet(context, packet);
        if (status == AVERROR(EAGAIN) || status == AVERROR_EOF)
            return;
        check(status);
        av_packet_rescale_ts(packet, context->time_base, stream->time_base);
        packet->stream_index = stream->index;
        check(av_interleaved_write_frame(container, packet));
    }
}

static void encode(enum AVCodecID id, const char *muxer, const int16_t *samples, uint64_t frames,
                   int rate, int channels, int setting, const char *path, int report)
{
    uint64_t started = micros();
    AVFormatContext *container = NULL;
    check(avformat_alloc_output_context2(&container, NULL, muxer, path));
    require(container != NULL, "Cannot allocate output container");
    const AVCodec *codec = avcodec_find_encoder(id);
    require(codec != NULL, "FFmpeg encoder is unavailable");
    AVCodecContext *context = avcodec_alloc_context3(codec);
    require(context != NULL, "Cannot allocate encoder");
    context->sample_rate = rate;
    context->sample_fmt = id == AV_CODEC_ID_AAC ? AV_SAMPLE_FMT_FLTP : AV_SAMPLE_FMT_S16;
    context->time_base = (AVRational){1, rate};
    context->thread_count = 1;
    av_channel_layout_default(&context->ch_layout, channels);
    if (id == AV_CODEC_ID_AAC) {
        context->profile = AV_PROFILE_AAC_LOW;
        context->bit_rate = setting;
        const char *cutoff = getenv("AUDIO_ENCODE_CUTOFF");
        if (cutoff)
            context->cutoff = number(cutoff, 0, rate / 2);
        check(av_opt_set(context->priv_data, "aac_coder", "twoloop", 0));
    } else if (id == AV_CODEC_ID_FLAC) {
        context->compression_level = setting;
    }
    if (container->oformat->flags & AVFMT_GLOBALHEADER)
        context->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    check(avcodec_open2(context, codec, NULL));
    AVStream *stream = avformat_new_stream(container, NULL);
    require(stream != NULL, "Cannot allocate output stream");
    stream->time_base = context->time_base;
    check(avcodec_parameters_from_context(stream->codecpar, context));
    check(avio_open(&container->pb, path, AVIO_FLAG_WRITE));
    check(avformat_write_header(container, NULL));

    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    require(packet && frame, "Cannot allocate encoder frame and packet");
    int block = context->frame_size > 0 ? context->frame_size : 4096;
    check(av_channel_layout_copy(&frame->ch_layout, &context->ch_layout));
    frame->sample_rate = rate;
    frame->format = context->sample_fmt;
    frame->nb_samples = block;
    check(av_frame_get_buffer(frame, 0));
    uint64_t opened = micros();
    for (uint64_t offset = 0; offset < frames;) {
        int count = frames - offset < (uint64_t)block ? (int)(frames - offset) : block;
        check(av_frame_make_writable(frame));
        frame->pts = (int64_t)offset;
        frame->nb_samples = count;
        const int16_t *input = samples + offset * channels;
        if (id == AV_CODEC_ID_AAC) {
            for (int channel = 0; channel < channels; ++channel) {
                float *planar = (float *)frame->extended_data[channel];
                for (int i = 0; i < count; ++i)
                    planar[i] = input[i * channels + channel] * (1.0f / 32768.0f);
            }
        } else {
            memcpy(frame->data[0], input, (size_t)count * channels * sizeof(*input));
        }
        check(avcodec_send_frame(context, frame));
        drain(context, container, stream, packet);
        offset += count;
    }
    uint64_t fed = micros();
    check(avcodec_send_frame(context, NULL));
    drain(context, container, stream, packet);
    check(av_write_trailer(container));
    check(avio_closep(&container->pb));
    int delay = context->initial_padding;
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&context);
    avformat_free_context(container);
    uint64_t finished = micros();
    if (report)
        printf("%llu %llu %llu %llu %llu %d\n",
               (unsigned long long)(opened - started), (unsigned long long)(fed - opened),
               (unsigned long long)(finished - fed), (unsigned long long)(finished - started),
               (unsigned long long)frames, delay);
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts(av_version_info());
        return 0;
    }
    require(argc == 8, "Usage: ffmpeg_native <codec> <pcm16> <rate> <channels> <setting> <output> <repetitions>");
    enum AVCodecID id = !strcmp(argv[1], "aac") ? AV_CODEC_ID_AAC :
                        !strcmp(argv[1], "flac") ? AV_CODEC_ID_FLAC :
                        !strcmp(argv[1], "wav") ? AV_CODEC_ID_PCM_S16LE : AV_CODEC_ID_NONE;
    require(id != AV_CODEC_ID_NONE, "Expected AAC, FLAC or WAV");
    const char *muxer = id == AV_CODEC_ID_AAC ? "adts" : argv[1];
    int rate = number(argv[3], 1, INT_MAX);
    int channels = number(argv[4], 1, 8);
    int setting = number(argv[5], id == AV_CODEC_ID_AAC ? 1 : 0,
                         id == AV_CODEC_ID_AAC ? INT_MAX : id == AV_CODEC_ID_FLAC ? 12 : 0);
    int repetitions = number(argv[7], 1, INT_MAX);
    uint64_t frames;
    int16_t *samples = read_pcm(argv[2], channels, &frames);
    av_log_set_level(AV_LOG_ERROR);
    encode(id, muxer, samples, frames, rate, channels, setting, argv[6], 0);
    for (int repeat = 0; repeat < repetitions; ++repeat)
        encode(id, muxer, samples, frames, rate, channels, setting, argv[6], 1);
    free(samples);
}
