#pragma once

#include <cstdint>
#include <string>

namespace prism {

struct LocalMediaMeta {
    int64_t durationMs = 0;
    int32_t width = 0;
    int32_t height = 0;
    std::string title;
    std::string mimeType;
};

LocalMediaMeta ProbeLocalMediaFd(int32_t fd, int64_t offset, int64_t size);

} // namespace prism
