#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <future>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "smb2_client.h"

namespace prism {

struct StreamConfig {
    std::string url;
    std::string authHeader;
    std::string userAgent = "PrismPlayer/1.0";
    bool allowInsecureTls = false;
    bool cacheAlist302 = true;
    // Optional explicit SMB parameters
    std::string smbHost;
    int smbPort = 445;
    std::string smbShare;
    std::string smbPath;
    std::string smbUser;
    std::string smbPass;
};

struct StreamStats {
    int64_t bytesServed = 0;
    int64_t cacheHits = 0;
    int64_t cacheMisses = 0;
    int64_t cachedBytes = 0;
    int64_t totalSize = -1;
    std::string resolvedUrl;
    int64_t resolvedAtMs = 0;
    std::string contentType = "application/octet-stream";
};

struct UpstreamChunkResult {
    int statusCode = 0;
    int64_t totalSize = -1;
    std::string contentType;
    std::string redirectUrl;
    std::vector<uint8_t> data;
};

using HttpsFetchDispatcher = std::function<void(
    int64_t reqId,
    const std::string& url,
    const std::string& authHeader,
    int64_t rangeStart,
    int64_t rangeEnd,
    bool allowInsecure)>;

class StreamRangeProxy {
public:
    static StreamRangeProxy& Instance();

    int Start(int cacheBudgetMb);
    void Stop();

    std::string RegisterStream(const std::string& streamId, const StreamConfig& config);
    void UnregisterStream(const std::string& streamId);
    StreamStats GetStats(const std::string& streamId);

    void SetHttpsDispatcher(HttpsFetchDispatcher dispatcher);
    void CompleteHttpsRequest(
        int64_t reqId,
        int statusCode,
        int64_t totalSize,
        const std::string& contentType,
        const std::string& redirectUrl,
        std::vector<uint8_t> data);

private:
    StreamRangeProxy() = default;
    ~StreamRangeProxy();

    void AcceptLoop();
    void HandleClient(int clientFd);
    UpstreamChunkResult FetchUpstreamRange(
        const std::string& streamId,
        const StreamConfig& config,
        int64_t rangeStart,
        int64_t rangeEnd,
        bool headOnly);
    UpstreamChunkResult FetchHttpSocket(
        const std::string& url,
        const std::string& authHeader,
        const std::string& userAgent,
        int64_t rangeStart,
        int64_t rangeEnd,
        bool headOnly,
        int redirectDepth);
    UpstreamChunkResult FetchViaHttpsBridge(
        const std::string& url,
        const std::string& authHeader,
        int64_t rangeStart,
        int64_t rangeEnd,
        bool allowInsecure);
    UpstreamChunkResult FetchViaSmb(
        const std::string& streamId,
        const StreamConfig& config,
        int64_t rangeStart,
        int64_t rangeEnd,
        bool headOnly);

    struct SmbOpenHandle {
        std::mutex opMutex;
        std::unique_ptr<Smb2Session> session;
        uint8_t fileId[16]{0};
        int64_t fileSize = -1;
        std::string openPath;
    };

    struct CacheKey {
        std::string streamId;
        int64_t blockIndex;
        bool operator==(const CacheKey& other) const {
            return blockIndex == other.blockIndex && streamId == other.streamId;
        }
    };
    struct CacheKeyHash {
        size_t operator()(const CacheKey& k) const {
            return std::hash<std::string>{}(k.streamId) ^ (std::hash<int64_t>{}(k.blockIndex) << 1);
        }
    };
    struct CacheEntry {
        CacheKey key;
        std::vector<uint8_t> data;
    };

    bool GetCachedBlock(const std::string& streamId, int64_t blockIndex, std::vector<uint8_t>& out);
    void PutCachedBlock(const std::string& streamId, int64_t blockIndex, std::vector<uint8_t> data);
    void EvictStreamCache(const std::string& streamId);

    // 与单次 SMB READ 上限对齐，块越大往返越少
    static constexpr int64_t kBlockSize = 1024 * 1024;
    // HEAD 探测只需拿到大小，不必拉整块
    static constexpr int64_t kProbeSize = 512 * 1024;

    std::atomic<bool> running_{false};
    int listenFd_ = -1;
    int port_ = 0;
    std::thread acceptThread_;

    std::mutex streamMutex_;
    std::unordered_map<std::string, StreamConfig> streams_;
    std::unordered_map<std::string, StreamStats> stats_;
    std::mutex smbMapMutex_;
    std::unordered_map<std::string, std::shared_ptr<SmbOpenHandle>> smbHandles_;

    std::mutex cacheMutex_;
    size_t maxCacheBytes_ = 64ULL * 1024ULL * 1024ULL;
    size_t currentCacheBytes_ = 0;
    std::list<CacheEntry> lruList_;
    std::unordered_map<CacheKey, std::list<CacheEntry>::iterator, CacheKeyHash> cacheMap_;

    std::mutex httpsMutex_;
    HttpsFetchDispatcher httpsDispatcher_;
    std::atomic<int64_t> nextReqId_{1};
    std::unordered_map<int64_t, std::promise<UpstreamChunkResult>> pendingHttps_;
};

} // namespace prism
