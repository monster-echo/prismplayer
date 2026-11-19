#pragma once

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_window/external_window.h>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>

namespace prism {

struct SurfaceRecord {
    OHNativeWindow* window = nullptr;
    uint64_t width = 0;
    uint64_t height = 0;
};

using SurfaceReadyCallback = std::function<void(const std::string& surfaceId, OHNativeWindow* window)>;

class XComponentBridge {
public:
    static XComponentBridge& Instance();

    void RegisterXComponent(OH_NativeXComponent* xcomponent, const std::string& surfaceId);
    OHNativeWindow* GetWindow(const std::string& surfaceId);
    void AddSurfaceListener(const std::string& surfaceId, SurfaceReadyCallback cb);
    void RemoveSurfaceListener(const std::string& surfaceId);

    void HandleSurfaceCreated(OH_NativeXComponent* component, void* window);
    void HandleSurfaceChanged(OH_NativeXComponent* component, void* window);
    void HandleSurfaceDestroyed(OH_NativeXComponent* component, void* window);

private:
    XComponentBridge() = default;
    std::string GetComponentId(OH_NativeXComponent* component);

    std::mutex mutex_;
    std::unordered_map<std::string, SurfaceRecord> surfaces_;
    std::unordered_map<OH_NativeXComponent*, std::string> componentIds_;
    std::unordered_map<std::string, SurfaceReadyCallback> listeners_;
    OH_NativeXComponent_Callback callback_{};
};

} // namespace prism
