#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fdk-aac/aacenc_lib.h>

#include "native_input.h"

static void check(AACENC_ERROR status)
{
    if (status != AACENC_OK) {
        fprintf(stderr, "FDK AAC encoder error 0x%04x\n", status);
        exit(1);
    }
}

static void encode(const int16_t *pcm, uint64_t frames, int rate, int channels, int bitrate,
                   const char *path, int report)
{
    uint64_t started = micros();
    HANDLE_AACENCODER encoder = NULL;
    check(aacEncOpen(&encoder, 0, channels));
    check(aacEncoder_SetParam(encoder, AACENC_AOT, 2));
    check(aacEncoder_SetParam(encoder, AACENC_SAMPLERATE, rate));
    check(aacEncoder_SetParam(encoder, AACENC_CHANNELMODE, channels == 1 ? MODE_1 : MODE_2));
    check(aacEncoder_SetParam(encoder, AACENC_BITRATE, bitrate));
    check(aacEncoder_SetParam(encoder, AACENC_TRANSMUX, TT_MP4_ADTS));
    check(aacEncoder_SetParam(encoder, AACENC_AFTERBURNER, 1));
    const char *cutoff = getenv("AUDIO_ENCODE_CUTOFF");
    if (cutoff)
        check(aacEncoder_SetParam(encoder, AACENC_BANDWIDTH, number(cutoff, 0, rate / 2)));
    check(aacEncEncode(encoder, NULL, NULL, NULL, NULL));

    AACENC_InfoStruct info = {0};
    check(aacEncInfo(encoder, &info));
    require(info.frameLength > 0 && info.maxOutBufBytes > 0, "Invalid FDK AAC dimensions");
    unsigned char *bytes = malloc(info.maxOutBufBytes);
    require(bytes != NULL, "Cannot allocate FDK AAC output");
    FILE *file = fopen(path, "wb");
    require(file != NULL, "Cannot open FDK AAC output");

    void *output = bytes;
    INT output_kind = OUT_BITSTREAM_DATA, output_size = info.maxOutBufBytes, byte_width = 1;
    AACENC_BufDesc out = {1, &output, &output_kind, &output_size, &byte_width};
    uint64_t opened = micros();
    uint64_t remaining = frames * channels;
    int full_block = info.frameLength * channels;
    while (remaining) {
        int samples = remaining < (uint64_t)full_block ? (int)remaining : full_block;
        void *input = (void *)pcm;
        INT input_kind = IN_AUDIO_DATA, input_size = samples * sizeof(*pcm), sample_width = sizeof(*pcm);
        AACENC_BufDesc in = {1, &input, &input_kind, &input_size, &sample_width};
        AACENC_InArgs in_args = {samples, 0};
        AACENC_OutArgs out_args = {0};
        check(aacEncEncode(encoder, &in, &out, &in_args, &out_args));
        require(out_args.numInSamples > 0 && out_args.numInSamples <= samples, "Invalid FDK AAC input consumption");
        require(fwrite(bytes, 1, out_args.numOutBytes, file) == (size_t)out_args.numOutBytes, "Incomplete FDK AAC output");
        pcm += out_args.numInSamples;
        remaining -= out_args.numInSamples;
    }

    uint64_t fed = micros();
    for (;;) {
        AACENC_InArgs in_args = {-1, 0};
        AACENC_OutArgs out_args = {0};
        AACENC_ERROR status = aacEncEncode(encoder, NULL, &out, &in_args, &out_args);
        if (status != AACENC_ENCODE_EOF)
            check(status);
        require(fwrite(bytes, 1, out_args.numOutBytes, file) == (size_t)out_args.numOutBytes, "Incomplete FDK AAC output");
        if (status == AACENC_ENCODE_EOF)
            break;
    }
    free(bytes);
    require(!fclose(file), "Cannot finalize FDK AAC output");
    check(aacEncClose(&encoder));
    uint64_t finished = micros();
    if (report)
        printf("%llu %llu %llu %llu %llu %u\n",
               (unsigned long long)(opened - started), (unsigned long long)(fed - opened),
               (unsigned long long)(finished - fed), (unsigned long long)(finished - started),
               (unsigned long long)frames, info.nDelay);
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts("FDK AAC " FDK_VERSION);
        return 0;
    }
    require(argc == 8 && !strcmp(argv[1], "aac"), "Usage: fdk_native aac PCM RATE CHANNELS BITRATE OUTPUT REPETITIONS");
    int rate = number(argv[3], 44100, 48000);
    int channels = number(argv[4], 1, 2);
    int bitrate = number(argv[5], 8000, INT_MAX);
    int repetitions = number(argv[7], 1, INT_MAX);
    uint64_t frames = 0;
    int16_t *pcm = read_pcm(argv[2], channels, &frames);
    for (uint64_t run = 0; run <= (uint64_t)repetitions; ++run)
        encode(pcm, frames, rate, channels, bitrate, argv[6], run != 0);
    free(pcm);
    return 0;
}
