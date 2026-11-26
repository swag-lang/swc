#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "agg_conv_stroke.h"
#include "agg_path_storage.h"
#include "agg_pixfmt_rgba.h"
#include "agg_rasterizer_scanline_aa.h"
#include "agg_renderer_base.h"
#include "agg_renderer_scanline.h"
#include "agg_scanline_p.h"

int main(int argc, char **argv)
{
    if (argc != 3)
        return 2;
    const std::string name = argv[1];
    const bool strokes = name == "strokes";
    if (!strokes && name != "fills")
        return 2;
    const unsigned batches = std::stoul(argv[2]);
    constexpr unsigned Width = 1200;
    constexpr unsigned Height = 900;
    using namespace agg;
    using Clock = std::chrono::steady_clock;
    for (unsigned repetition = 0; repetition <= batches; ++repetition)
    {
        const auto begin = Clock::now();
        std::vector<unsigned char> surface(Width * Height * 4, 255);
        rendering_buffer pixels(surface.data(), Width, Height, Width * 4);
        pixfmt_bgra32 format(pixels);
        renderer_base<pixfmt_bgra32> renderer(format);
        rasterizer_scanline_aa<> rasterizer;
        scanline_p8 line;
        path_storage path;
        conv_stroke<path_storage> outline(path);
        outline.width(2.25);
        outline.line_join(round_join);
        outline.line_cap(butt_cap);
        for (int i = 0; i < 1200; ++i)
        {
            const auto x = (i * 37) % 1056 + 0.25;
            const auto y = (i * 19) % 820 + 36.625;
            path.remove_all();
            path.move_to(x, y);
            for (int j = 1; j <= 7; ++j)
            {
                const int offset = (i * 5 + j * j * 9) % 43 - 21;
                path.line_to(x + j * 16, y + offset);
            }

            rasterizer.reset();
            if (strokes)
                rasterizer.add_path(outline);
            else
            {
                path.line_to(x + 112, y + 30);
                path.line_to(x, y + 30);
                path.close_polygon();
                rasterizer.add_path(path);
            }
            render_scanlines_aa_solid(rasterizer, line, renderer, rgba8(0, 0, 0));
        }

        const auto finish = Clock::now();
        if (repetition)
        {
            uint64_t coverage = 0;
            for (size_t i = 0; i < surface.size(); i += 4)
                coverage += 255u - surface[i];
            const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(finish - begin).count();
            std::cout << 1000000000 << ' ' << 0 << ' ' << ns << ' ' << coverage << '\n';
        }
    }
}
