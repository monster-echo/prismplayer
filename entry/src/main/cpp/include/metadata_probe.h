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
    // 音频标签：音乐库分组优先用内嵌 tag，缺失时再由文件名 / 目录推断
    std::string artist;
    std::string album;
};

LocalMediaMeta ProbeLocalMediaFd(int32_t fd, int64_t offset, int64_t size);

} // namespace prism
