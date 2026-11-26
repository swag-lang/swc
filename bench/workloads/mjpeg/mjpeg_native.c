#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <jpeglib.h>

struct picture
{
    unsigned char *data;
    size_t size;
    AVPacket *packet;
};

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
    struct timespec value;
    if (clock_gettime(clock, &value))
        abort();
    return (uint64_t)value.tv_sec * 1000000000 + value.tv_nsec;
}

static void encode_turbo(const unsigned char *rgb, int width, int height, int quality,
                         struct picture *pictures, int count)
{
    struct jpeg_compress_struct info;
    struct jpeg_error_mgr errors;
    info.err = jpeg_std_error(&errors);
    jpeg_create_compress(&info);
    info.image_width = width;
    info.image_height = height;
    info.input_components = 3;
    info.in_color_space = JCS_RGB;
    jpeg_set_defaults(&info);
    jpeg_set_quality(&info, quality, TRUE);
    for (int component = 0; component < 3; ++component)
    {
        info.comp_info[component].h_samp_factor = 1;
        info.comp_info[component].v_samp_factor = 1;
    }
    const size_t stride = (size_t)width * 3;
    for (int i = 0; i < count; ++i)
    {
        unsigned long length = 0;
        jpeg_mem_dest(&info, &pictures[i].data, &length);
        jpeg_start_compress(&info, TRUE);
        for (int row = height - 1; row >= 0; --row)
        {
            JSAMPROW source = (JSAMPROW)(rgb + row * stride);
            jpeg_write_scanlines(&info, &source, 1);
        }
        jpeg_finish_compress(&info);
        pictures[i].size = length;
        rgb += stride * height;
    }
    jpeg_destroy_compress(&info);
}

static void encode_ffmpeg(const unsigned char *rgb, int width, int height, int quality,
                          struct picture *pictures, int count)
{
    const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_MJPEG);
    if (!encoder)
        check(AVERROR_ENCODER_NOT_FOUND);
    AVCodecContext *codec = avcodec_alloc_context3(encoder);
    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();
    if (!codec || !frame || !packet)
        check(AVERROR(ENOMEM));
    codec->width = width;
    codec->height = height;
    codec->time_base = (AVRational){1, 30};
    codec->thread_count = 1;
    codec->pix_fmt = AV_PIX_FMT_YUV444P;
    codec->color_range = AVCOL_RANGE_JPEG;
    codec->colorspace = AVCOL_SPC_BT470BG;
    codec->flags |= AV_CODEC_FLAG_QSCALE;
    codec->global_quality = quality * FF_QP2LAMBDA;
    check(avcodec_open2(codec, encoder, NULL));
    frame->width = width;
    frame->height = height;
    frame->format = codec->pix_fmt;
    frame->color_range = codec->color_range;
    frame->colorspace = codec->colorspace;
    frame->quality = codec->global_quality;
    check(av_frame_get_buffer(frame, 32));
    struct SwsContext *convert = sws_getContext(width, height, AV_PIX_FMT_RGB24, width, height,
                                               codec->pix_fmt, SWS_POINT, NULL, NULL, NULL);
    if (!convert)
        check(AVERROR(ENOMEM));
    const int *coefficients = sws_getCoefficients(SWS_CS_ITU601);
    check(sws_setColorspaceDetails(convert, coefficients, 1, coefficients, 1, 0, 1 << 16, 1 << 16));
    const int stride = width * 3;
    const int lines[4] = {-stride, 0, 0, 0};
    for (int i = 0; i < count; ++i)
    {
        const uint8_t *source[4] = {rgb + (size_t)stride * (height - 1), NULL, NULL, NULL};
        check(av_frame_make_writable(frame));
        if (sws_scale(convert, source, lines, 0, height, frame->data, frame->linesize) != height)
            check(AVERROR_INVALIDDATA);
        frame->pts = i;
        check(avcodec_send_frame(codec, frame));
        check(avcodec_receive_packet(codec, packet));
        pictures[i].packet = av_packet_alloc();
        if (!pictures[i].packet)
            check(AVERROR(ENOMEM));
        av_packet_move_ref(pictures[i].packet, packet);
        pictures[i].data = pictures[i].packet->data;
        pictures[i].size = pictures[i].packet->size;
        rgb += (size_t)stride * height;
    }
    check(avcodec_send_frame(codec, NULL));
    if (avcodec_receive_packet(codec, packet) != AVERROR_EOF)
        check(AVERROR_INVALIDDATA);
    sws_freeContext(convert);
    av_packet_free(&packet);
    av_frame_free(&frame);
    avcodec_free_context(&codec);
}

int main(int argc, char **argv)
{
    if (argc != 8 || (strcmp(argv[1], "turbo") && strcmp(argv[1], "ffmpeg")))
    {
        fprintf(stderr, "usage: mjpeg_native turbo|ffmpeg input.rgb output.mjpg width height count quality\n");
        return 2;
    }
    const int turbo = !strcmp(argv[1], "turbo");
    const int width = number(argv[4], 1, 65000);
    const int height = number(argv[5], 1, 65000);
    const int count = number(argv[6], 1, 10000);
    const int quality = number(argv[7], turbo ? 1 : 2, turbo ? 100 : 31);
    const size_t length = (size_t)width * height * 3 * count;
    unsigned char *rgb = malloc(length);
    struct picture *pictures = calloc(count, sizeof(*pictures));
    if (!rgb || !pictures)
        check(AVERROR(ENOMEM));
    FILE *input = fopen(argv[2], "rb");
    if (!input)
        check(AVERROR(errno));
    if (fread(rgb, 1, length, input) != length || fgetc(input) != EOF || ferror(input))
        check(AVERROR_INVALIDDATA);
    fclose(input);

    uint64_t wall = ticks(CLOCK_MONOTONIC);
    uint64_t cpu = ticks(CLOCK_PROCESS_CPUTIME_ID);
    if (turbo)
        encode_turbo(rgb, width, height, quality, pictures, count);
    else
        encode_ffmpeg(rgb, width, height, quality, pictures, count);
    cpu = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu;
    wall = ticks(CLOCK_MONOTONIC) - wall;

    FILE *output = fopen(argv[3], "wb");
    if (!output)
        check(AVERROR(errno));
    size_t packets = 0;
    for (int i = 0; i < count; ++i)
    {
        if (fwrite(pictures[i].data, 1, pictures[i].size, output) != pictures[i].size)
            check(AVERROR(EIO));
        packets += pictures[i].size;
        if (pictures[i].packet)
            av_packet_free(&pictures[i].packet);
        else
            free(pictures[i].data);
    }
    if (fclose(output))
        check(AVERROR(errno));
    free(pictures);
    free(rgb);
    printf("MJPEG frames=%d us=%" PRIu64 " cpu_us=%" PRIu64 " bytes=%zu\n", count, wall / 1000, cpu / 1000, packets);
}
