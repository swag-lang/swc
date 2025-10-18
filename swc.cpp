#include <iostream>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

void parseFolder(const fs::path& directory) {
    if (!fs::exists(directory) || !fs::is_directory(directory)) {
        std::cerr << "Invalid directory: " << directory << std::endl;
        return;
    }

    for (const auto& entry : fs::recursive_directory_iterator(directory)) {
        if (entry.is_regular_file()) {
            auto ext = entry.path().extension().string();
            if (ext == ".swg" || ext == ".swgs") {
                // std::cout << entry.path().string() << std::endl;
                // You can add your file parsing logic here
            }
        }
    }
}

int main(int argc, char* argv[])
{
    parseFolder("c:/perso/swag-lang");
    return 0;
}
