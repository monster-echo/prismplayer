#pragma once

#include <multimedia/player_framework/avplayer.h>
#include <multimedia/player_framework/avplayer_base.h>
#include <native_window/external_window.h>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace prism {

struct TrackInfo {
    int32_t index = -1;
    int32_t trackType = -1; // 0: audio, 1: video, 2: subtitle
    std::string mimeType;
    std::string language;
    std::string title;
    int32_t sampleRate = 0;
    int32_t channels = 0;
    int32_t width = 0;
    int32_t height = 0;
};

struct PlayerEvent {
    std::string type;
    int32_t state = 0;
    int32_t positionMs = 0;
    int64_t durationMs = 0;
    int32_t width = 0;
    int32_t height = 0;
    int32_t bufferingType = 0;
    int32_t bufferingValue = 0;
    float rate = 1.0f;
    int32_t errorCode = 0;
    std::string errorMsg;
};

using PlayerEventCallback = std::function<void(const PlayerEvent& event)>;

class NativePlayerEngine {
public:
    explicit NativePlayerEngine(int32_t id);
    ~NativePlayerEngine();

    int32_t Id() const { return id_; }
    bool BindSurface(const std::string& surfaceId);
    int32_t SetUrlSource(const std::string& url);
    int32_t SetFdSource(int32_t fd, int64_t offset, int64_t size);
    int32_t Prepare();
    int32_t Play();
    int32_t Pause();
    int32_t Stop();
    int32_t Reset();
    int32_t Seek(int32_t positionMs, int32_t mode);
    int32_t SetRate(float rate);
    int32_t SetVolume(float volume);
    int32_t SelectTrack(int32_t trackIndex);
    int32_t DeselectTrack(int32_t trackIndex);
    std::vector<TrackInfo> GetTracks();
    void SetEventCallback(PlayerEventCallback callback);

private:
    static void OnPlayerInfo(OH_AVPlayer* player, AVPlayerOnInfoType type, OH_AVFormat* infoBody, void* userData);
    static void OnPlayerError(OH_AVPlayer* player, int32_t errorCode, const char* errorMsg, void* userData);

    void EmitEvent(const PlayerEvent& event);
    void ApplySurfaceIfReady(OHNativeWindow* window);

    int32_t id_;
    OH_AVPlayer* player_ = nullptr;
    std::string surfaceId_;
    std::mutex mutex_;
    PlayerEventCallback eventCallback_;
};

} // namespace prism
