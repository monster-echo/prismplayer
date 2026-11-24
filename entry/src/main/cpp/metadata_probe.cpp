#include "metadata_probe.h"
#include <multimedia/player_framework/avmetadata_extractor.h>
#include <multimedia/player_framework/avmetadata_extractor_base.h>
#include <multimedia/player_framework/native_avformat.h>

namespace prism {

LocalMediaMeta ProbeLocalMediaFd(int32_t fd, int64_t offset, int64_t size) {
    LocalMediaMeta meta;
    if (fd < 0 || size <= 0) {
        return meta;
    }

    OH_AVMetadataExtractor* extractor = OH_AVMetadataExtractor_Create();
    if (!extractor) {
        return meta;
    }

    if (OH_AVMetadataExtractor_SetFDSource(extractor, fd, offset, size) == AV_ERR_OK) {
        OH_AVFormat* format = OH_AVFormat_Create();
        if (format) {
            if (OH_AVMetadataExtractor_FetchMetadata(extractor, format) == AV_ERR_OK) {
                int64_t dur = 0;
                if (OH_AVFormat_GetLongValue(format, OH_AVMETADATA_EXTRACTOR_DURATION, &dur)) {
                    meta.durationMs = dur;
                }
                int32_t w = 0;
                int32_t h = 0;
                if (OH_AVFormat_GetIntValue(format, OH_AVMETADATA_EXTRACTOR_VIDEO_WIDTH, &w)) {
                    meta.width = w;
                }
                if (OH_AVFormat_GetIntValue(format, OH_AVMETADATA_EXTRACTOR_VIDEO_HEIGHT, &h)) {
                    meta.height = h;
                }
                const char* title = nullptr;
                if (OH_AVFormat_GetStringValue(format, OH_AVMETADATA_EXTRACTOR_TITLE, &title) && title) {
                    meta.title = title;
                }
                const char* mime = nullptr;
                if (OH_AVFormat_GetStringValue(format, OH_AVMETADATA_EXTRACTOR_MIME_TYPE, &mime) && mime) {
                    meta.mimeType = mime;
                }
                const char* artist = nullptr;
                if (OH_AVFormat_GetStringValue(format, OH_AVMETADATA_EXTRACTOR_ARTIST, &artist) && artist) {
                    meta.artist = artist;
                }
                const char* album = nullptr;
                if (OH_AVFormat_GetStringValue(format, OH_AVMETADATA_EXTRACTOR_ALBUM, &album) && album) {
                    meta.album = album;
                }
            }
            OH_AVFormat_Destroy(format);
        }
    }

    OH_AVMetadataExtractor_Release(extractor);
    return meta;
}

} // namespace prism
