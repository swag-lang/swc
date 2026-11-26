#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>

static uint64_t micros(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec * UINT64_C(1000000) + time.tv_nsec / 1000;
}

static void check(int result) {
    if (result < 0) {
        char error[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(result, error, sizeof(error));
        fprintf(stderr, "%s\n", error);
        exit(1);
    }
}

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

static void write_pcm(const char *path, const int16_t *samples, size_t count)
{
    FILE *file = fopen(path, "wb");
    require(file != NULL, "Cannot open PCM output");
    require(fwrite(samples, sizeof(*samples), count, file) == count, "Incomplete PCM output");
    require(!fclose(file), "Cannot close PCM output");
}

static void run(const char *path, int print, int threads, const char *pcm_path)
{
    uint64_t started = micros();
    AVFormatContext *container = NULL;
    check(avformat_open_input(&container, path, NULL, NULL));
    check(avformat_find_stream_info(container, NULL));
    const AVCodec *codec;
    int index = av_find_best_stream(container, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
    check(index);
    AVCodecContext *context = avcodec_alloc_context3(codec);
    require(context != NULL, "Cannot allocate decoder");
    check(avcodec_parameters_to_context(context, container->streams[index]->codecpar));
    context->thread_count = threads;
    check(avcodec_open2(context, codec, NULL));
    uint64_t opened = micros();

    int channels = context->ch_layout.nb_channels;
    int rate = context->sample_rate;
    int frames = 10 * rate;
    require(channels > 0 && frames > 0, "Audio dimensions must be known at open");
    int16_t *samples = malloc((size_t)frames * channels * sizeof(*samples));
    require(samples != NULL, "Cannot allocate PCM");
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    require(packet && frame, "Cannot allocate packet and frame");
    SwrContext *resample = NULL;
    int written = 0;
    int draining = 0;
    while (written < frames) {
        int status = av_read_frame(container, packet);
        if (status == AVERROR_EOF) {
            draining = 1;
            check(avcodec_send_packet(context, NULL));
        } else {
            check(status);
            if (packet->stream_index != index) {
                av_packet_unref(packet);
                continue;
            }
            check(avcodec_send_packet(context, packet));
            av_packet_unref(packet);
        }
        while (written < frames) {
            status = avcodec_receive_frame(context, frame);
            if (status == AVERROR(EAGAIN) || status == AVERROR_EOF)
                break;
            check(status);
            require(rate == frame->sample_rate && channels == frame->ch_layout.nb_channels,
                "Audio dimensions changed during decode");
            if (!resample) {
                check(swr_alloc_set_opts2(&resample, &context->ch_layout, AV_SAMPLE_FMT_S16,
                    context->sample_rate, &frame->ch_layout, frame->format, frame->sample_rate, 0, NULL));
                check(swr_init(resample));
            }
            uint8_t *destination = (uint8_t *)(samples + (size_t)written * channels);
            int count = swr_convert(resample, &destination, frames - written,
                (const uint8_t **)frame->extended_data, frame->nb_samples);
            check(count);
            written += count;
            av_frame_unref(frame);
        }
        if (draining)
            break;
    }
    require(written > 0, "No audio frames decoded");
    uint64_t finished = micros();
    if (print)
        printf("%llu %llu %llu %d %d %d\n", (unsigned long long)(opened - started),
            (unsigned long long)(finished - opened), (unsigned long long)(finished - started),
            written, channels, rate);
    if (pcm_path)
        write_pcm(pcm_path, samples, (size_t)written * channels);
    swr_free(&resample);
    av_frame_free(&frame);
    av_packet_free(&packet);
    free(samples);
    avcodec_free_context(&context);
    avformat_close_input(&container);
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts(av_version_info());
        return 0;
    }
    require(argc == 3 || argc == 4, "Usage: ffmpeg_native <fixture> <threads> [pcm-output]");
    char *end;
    errno = 0;
    long threads = strtol(argv[2], &end, 10);
    require(!errno && !*end && threads > 0 && threads <= 256, "Invalid decoder thread count");
    av_log_set_level(AV_LOG_ERROR);
    run(argv[1], 0, (int)threads, NULL);
    for (int sample = 0; sample < 7; ++sample)
        run(argv[1], 1, (int)threads, sample == 6 && argc == 4 ? argv[3] : NULL);
}
