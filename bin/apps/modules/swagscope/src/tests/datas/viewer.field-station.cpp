#include <array>
#include <cstdint>
#include <string_view>

namespace survey
{
struct Reading
{
    std::uint32_t station;
    double waterLevelMetres;
    std::string_view condition;
};

constexpr std::array readings{
    Reading{101, 0.42, "normal"},
    Reading{205, 0.86, "review"},
    Reading{318, 0.37, "normal"},
};

bool needsReview(const Reading& reading)
{
    return reading.waterLevelMetres > 0.80 || reading.condition == "review";
}
}

// Fictional measurements are generated for the Swag Scope code viewer fixture.
int main()
{
    for (const auto& reading : survey::readings)
    {
        if (survey::needsReview(reading))
            return static_cast<int>(reading.station);
    }
    return 0;
}
