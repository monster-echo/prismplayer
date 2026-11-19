#include "stream_proxy.h"
#include <arpa/inet.h>
#include <chrono>
#include <cstring>
#include <hilog/log.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <algorithm>
#include <cctype>

#undef LOG_TAG
#define LOG_TAG "PrismStreamProxy"

namespace prism {

namespace {

int64_t NowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

std::string ToLower(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

std::string Trim(const std::string& s) {
    size_t start = 0;
    while (start < s.size() && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r' || s[start] == '\n')) {
        ++start;
    }
    size_t end = s.size();
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r' || s[end - 1] == '\n')) {
        --end;
    }
    return s.substr(start, end - start);
}

struct ParsedUrl {
    std::string scheme;
    std::string host;
    std::string port;
    std::string path;
    bool valid = false;
};

ParsedUrl ParseUrl(const std::string& url) {
    ParsedUrl out;
    size_t schemeEnd = url.find("://");
    if (schemeEnd == std::string::npos) return out;
    out.scheme = ToLower(url.substr(0, schemeEnd));
    size_t hostStart = schemeEnd + 3;
    size_t pathStart = url.find('/', hostStart);
    std::string hostPort = (pathStart == std::string::npos)
        ? url.substr(hostStart)
        : url.substr(hostStart, pathStart - hostStart);
    out.path = (pathStart == std::string::npos) ? "/" : url.substr(pathStart);

    // Handle IPv6 [::1]:port or host:port
    if (!hostPort.empty() && hostPort[0] == '[') {
        size_t closeBracket = hostPort.find(']');
        if (closeBracket == std::string::npos) return out;
        out.host = hostPort.substr(1, closeBracket - 1);
        if (closeBracket + 1 < hostPort.size() && hostPort[closeBracket + 1] == ':') {
            out.port = hostPort.substr(closeBracket + 2);
        }
    } else {
        size_t colon = hostPort.rfind(':');
        if (colon != std::string::npos) {
            out.host = hostPort.substr(0, colon);
            out.port = hostPort.substr(colon + 1);
        } else {
            out.host = hostPort;
        }
    }
    if (out.port.empty()) {
        out.port = (out.scheme == "https") ? "443" : "80";
    }
    out.valid = !out.host.empty();
    return out;
}

bool SendAll(int fd, const uint8_t* data, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, data + sent, len - sent, MSG_NOSIGNAL);
        if (n <= 0) {
            return false;
        }
        sent += static_cast<size_t>(n);
    }
    return true;
}

bool SendStr(int fd, const std::string& s) {
    return SendAll(fd, reinterpret_cast<const uint8_t*>(s.data()), s.size());
}

} // namespace

StreamRangeProxy& StreamRangeProxy::Instance() {
    static StreamRangeProxy instance;
    return instance;
}

StreamRangeProxy::~StreamRangeProxy() {
    Stop();
}

int StreamRangeProxy::Start(int cacheBudgetMb) {
    if (cacheBudgetMb < 16) cacheBudgetMb = 16;
    if (cacheBudgetMb > 256) cacheBudgetMb = 256;
    {
        std::lock_guard<std::mutex> lock(cacheMutex_);
        maxCacheBytes_ = static_cast<size_t>(cacheBudgetMb) * 1024ULL * 1024ULL;
    }

    if (running_.load()) {
        return port_;
    }

    listenFd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd_ < 0) {
        OH_LOG_ERROR(LOG_APP, "Failed to create loopback proxy socket");
        return 0;
    }

    int opt = 1;
    setsockopt(listenFd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0; // Ephemeral port

    if (bind(listenFd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        OH_LOG_ERROR(LOG_APP, "Failed to bind loopback proxy socket");
        close(listenFd_);
        listenFd_ = -1;
        return 0;
    }

    if (listen(listenFd_, 16) < 0) {
        OH_LOG_ERROR(LOG_APP, "Failed to listen loopback proxy socket");
        close(listenFd_);
        listenFd_ = -1;
        return 0;
    }

    socklen_t len = sizeof(addr);
    getsockname(listenFd_, reinterpret_cast<sockaddr*>(&addr), &len);
    port_ = ntohs(addr.sin_port);
    running_.store(true);

    acceptThread_ = std::thread(&StreamRangeProxy::AcceptLoop, this);
    OH_LOG_INFO(LOG_APP, "StreamRangeProxy started on 127.0.0.1:%{public}d (cache=%{public}dMB)", port_, cacheBudgetMb);
    return port_;
}

void StreamRangeProxy::Stop() {
    if (!running_.exchange(false)) {
        return;
    }
    if (listenFd_ >= 0) {
        shutdown(listenFd_, SHUT_RDWR);
        close(listenFd_);
        listenFd_ = -1;
    }
    if (acceptThread_.joinable()) {
        acceptThread_.join();
    }
    port_ = 0;
}

std::string StreamRangeProxy::RegisterStream(const std::string& streamId, const StreamConfig& config) {
    if (!running_.load()) {
        Start(64);
    }
    {
        std::lock_guard<std::mutex> lock(streamMutex_);
        streams_[streamId] = config;
        StreamStats st;
        st.resolvedUrl = config.url;
        stats_[streamId] = st;
    }
    EvictStreamCache(streamId);
    return "http://127.0.0.1:" + std::to_string(port_) + "/stream/" + streamId;
}

void StreamRangeProxy::UnregisterStream(const std::string& streamId) {
    {
        std::lock_guard<std::mutex> lock(streamMutex_);
        streams_.erase(streamId);
        stats_.erase(streamId);
    }
    {
        std::lock_guard<std::mutex> slock(smbMapMutex_);
        smbHandles_.erase(streamId);
    }
    EvictStreamCache(streamId);
}

StreamStats StreamRangeProxy::GetStats(const std::string& streamId) {
    std::lock_guard<std::mutex> lock(streamMutex_);
    auto it = stats_.find(streamId);
    if (it != stats_.end()) {
        StreamStats s = it->second;
        std::lock_guard<std::mutex> clock(cacheMutex_);
        s.cachedBytes = static_cast<int64_t>(currentCacheBytes_);
        return s;
    }
    return StreamStats{};
}

void StreamRangeProxy::SetHttpsDispatcher(HttpsFetchDispatcher dispatcher) {
    std::lock_guard<std::mutex> lock(httpsMutex_);
    httpsDispatcher_ = std::move(dispatcher);
}

void StreamRangeProxy::CompleteHttpsRequest(
    int64_t reqId,
    int statusCode,
    int64_t totalSize,
    const std::string& contentType,
    const std::string& redirectUrl,
    std::vector<uint8_t> data) {
    std::lock_guard<std::mutex> lock(httpsMutex_);
    auto it = pendingHttps_.find(reqId);
    if (it != pendingHttps_.end()) {
        UpstreamChunkResult res;
        res.statusCode = statusCode;
        res.totalSize = totalSize;
        res.contentType = contentType;
        res.redirectUrl = redirectUrl;
        res.data = std::move(data);
        it->second.set_value(std::move(res));
        pendingHttps_.erase(it);
    }
}

void StreamRangeProxy::AcceptLoop() {
    while (running_.load()) {
        sockaddr_in clientAddr{};
        socklen_t clientLen = sizeof(clientAddr);
        int clientFd = accept(listenFd_, reinterpret_cast<sockaddr*>(&clientAddr), &clientLen);
        if (clientFd < 0) {
            if (!running_.load()) break;
            continue;
        }
        std::thread([this, clientFd]() {
            HandleClient(clientFd);
            close(clientFd);
        }).detach();
    }
}

void StreamRangeProxy::HandleClient(int clientFd) {
    struct timeval tv{10, 0};
    setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    std::string reqBuf;
    reqBuf.reserve(2048);
    char tmp[1024];
    while (reqBuf.find("\r\n\r\n") == std::string::npos && reqBuf.size() < 16384) {
        ssize_t n = recv(clientFd, tmp, sizeof(tmp), 0);
        if (n <= 0) return;
        reqBuf.append(tmp, static_cast<size_t>(n));
    }

    std::istringstream iss(reqBuf);
    std::string method, target, version;
    iss >> method >> target >> version;
    if (method.empty() || target.empty()) {
        SendStr(clientFd, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    }

    const std::string prefix = "/stream/";
    if (target.rfind(prefix, 0) != 0) {
        SendStr(clientFd, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    }
    std::string streamId = target.substr(prefix.size());
    size_t qpos = streamId.find('?');
    if (qpos != std::string::npos) streamId = streamId.substr(0, qpos);

    StreamConfig config;
    StreamStats existingStats;
    {
        std::lock_guard<std::mutex> lock(streamMutex_);
        auto it = streams_.find(streamId);
        if (it == streams_.end()) {
            SendStr(clientFd, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            return;
        }
        config = it->second;
        existingStats = stats_[streamId];
    }

    int64_t reqStart = 0;
    int64_t reqEnd = -1;
    bool hasRange = false;
    std::string line;
    std::getline(iss, line);
    while (std::getline(iss, line)) {
        std::string lower = ToLower(line);
        if (lower.rfind("range:", 0) == 0) {
            std::string val = Trim(line.substr(6));
            if (val.rfind("bytes=", 0) == 0) {
                hasRange = true;
                std::string spec = val.substr(6);
                size_t dash = spec.find('-');
                if (dash != std::string::npos) {
                    std::string s1 = Trim(spec.substr(0, dash));
                    std::string s2 = Trim(spec.substr(dash + 1));
                    if (!s1.empty()) reqStart = std::stoll(s1);
                    if (!s2.empty()) reqEnd = std::stoll(s2);
                }
            }
        }
    }

    bool headOnly = (method == "HEAD");
    int64_t totalSize = existingStats.totalSize;
    std::string contentType = existingStats.contentType;

    // Probe total size if unknown
    if (totalSize <= 0 || headOnly) {
        UpstreamChunkResult probe = FetchUpstreamRange(streamId, config, 0, kBlockSize - 1, headOnly);
        if (probe.statusCode == 0 || probe.statusCode >= 400) {
            SendStr(clientFd, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            return;
        }
        if (probe.totalSize > 0) totalSize = probe.totalSize;
        if (!probe.contentType.empty()) contentType = probe.contentType;
        if (!probe.data.empty()) {
            PutCachedBlock(streamId, 0, std::move(probe.data));
        }
        {
            std::lock_guard<std::mutex> lock(streamMutex_);
            auto sit = stats_.find(streamId);
            if (sit != stats_.end()) {
                if (totalSize > 0) sit->second.totalSize = totalSize;
                if (!contentType.empty()) sit->second.contentType = contentType;
            }
        }
        if (headOnly) {
            std::ostringstream hdr;
            hdr << "HTTP/1.1 200 OK\r\n"
                << "Accept-Ranges: bytes\r\n"
                << "Content-Type: " << contentType << "\r\n";
            if (totalSize > 0) hdr << "Content-Length: " << totalSize << "\r\n";
            hdr << "Connection: close\r\n\r\n";
            SendStr(clientFd, hdr.str());
            return;
        }
    }

    if (totalSize <= 0) {
        SendStr(clientFd, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    }

    if (reqStart < 0) reqStart = 0;
    if (reqStart >= totalSize) {
        SendStr(clientFd, "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */" +
                std::to_string(totalSize) + "\r\nConnection: close\r\n\r\n");
        return;
    }
    if (reqEnd < 0 || reqEnd >= totalSize) {
        reqEnd = totalSize - 1;
    }

    int64_t contentLen = reqEnd - reqStart + 1;
    std::ostringstream respHdr;
    if (hasRange) {
        respHdr << "HTTP/1.1 206 Partial Content\r\n"
                << "Content-Range: bytes " << reqStart << "-" << reqEnd << "/" << totalSize << "\r\n";
    } else {
        respHdr << "HTTP/1.1 200 OK\r\n";
    }
    respHdr << "Accept-Ranges: bytes\r\n"
            << "Content-Type: " << contentType << "\r\n"
            << "Content-Length: " << contentLen << "\r\n"
            << "Connection: close\r\n\r\n";
    if (!SendStr(clientFd, respHdr.str())) {
        return;
    }

    int64_t cursor = reqStart;
    while (cursor <= reqEnd && running_.load()) {
        int64_t blockIdx = cursor / kBlockSize;
        int64_t blockOffset = cursor % kBlockSize;
        int64_t blockStart = blockIdx * kBlockSize;
        int64_t blockEnd = std::min(blockStart + kBlockSize - 1, totalSize - 1);

        std::vector<uint8_t> blockData;
        bool hit = GetCachedBlock(streamId, blockIdx, blockData);
        if (hit) {
            std::lock_guard<std::mutex> lock(streamMutex_);
            stats_[streamId].cacheHits++;
        } else {
            UpstreamChunkResult fetched = FetchUpstreamRange(streamId, config, blockStart, blockEnd, false);
            if (fetched.statusCode == 0 || fetched.statusCode >= 400 || fetched.data.empty()) {
                break;
            }
            {
                std::lock_guard<std::mutex> lock(streamMutex_);
                stats_[streamId].cacheMisses++;
            }
            blockData = fetched.data;
            PutCachedBlock(streamId, blockIdx, std::move(fetched.data));
        }

        if (blockOffset >= static_cast<int64_t>(blockData.size())) {
            break;
        }
        int64_t available = static_cast<int64_t>(blockData.size()) - blockOffset;
        int64_t toSend = std::min(available, reqEnd - cursor + 1);
        if (!SendAll(clientFd, blockData.data() + blockOffset, static_cast<size_t>(toSend))) {
            break;
        }
        cursor += toSend;
        {
            std::lock_guard<std::mutex> lock(streamMutex_);
            stats_[streamId].bytesServed += toSend;
        }
    }
}

UpstreamChunkResult StreamRangeProxy::FetchUpstreamRange(
    const std::string& streamId,
    const StreamConfig& config,
    int64_t rangeStart,
    int64_t rangeEnd,
    bool headOnly) {
    if (!config.smbHost.empty() ||
        config.url.rfind("smb://", 0) == 0 ||
        config.url.rfind("SMB://", 0) == 0) {
        return FetchViaSmb(streamId, config, rangeStart, rangeEnd, headOnly);
    }

    std::string targetUrl = config.url;
    std::string authHeader = config.authHeader;

    // Reuse Alist 302 cached direct URL if valid within 10 minutes
    if (config.cacheAlist302) {
        std::lock_guard<std::mutex> lock(streamMutex_);
        auto sit = stats_.find(streamId);
        if (sit != stats_.end() && !sit->second.resolvedUrl.empty() &&
            sit->second.resolvedUrl != config.url &&
            (NowMs() - sit->second.resolvedAtMs) < 600000) {
            targetUrl = sit->second.resolvedUrl;
            // Direct CDN URLs usually reject upstream WebDAV Basic Auth header
            authHeader.clear();
        }
    }

    ParsedUrl parsed = ParseUrl(targetUrl);
    if (!parsed.valid) {
        return UpstreamChunkResult{};
    }

    UpstreamChunkResult res;
    if (parsed.scheme == "http") {
        res = FetchHttpSocket(targetUrl, authHeader, config.userAgent, rangeStart, rangeEnd, headOnly, 0);
    } else {
        res = FetchViaHttpsBridge(targetUrl, authHeader, rangeStart, rangeEnd, config.allowInsecureTls);
    }

    // If cached 302 URL expired (401/403/404), retry original WebDAV URL once
    if ((res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404) && targetUrl != config.url) {
        {
            std::lock_guard<std::mutex> lock(streamMutex_);
            stats_[streamId].resolvedUrl = config.url;
            stats_[streamId].resolvedAtMs = 0;
        }
        ParsedUrl orig = ParseUrl(config.url);
        if (orig.scheme == "http") {
            res = FetchHttpSocket(config.url, config.authHeader, config.userAgent, rangeStart, rangeEnd, headOnly, 0);
        } else {
            res = FetchViaHttpsBridge(config.url, config.authHeader, rangeStart, rangeEnd, config.allowInsecureTls);
        }
    }

    if (!res.redirectUrl.empty() && config.cacheAlist302) {
        std::lock_guard<std::mutex> lock(streamMutex_);
        stats_[streamId].resolvedUrl = res.redirectUrl;
        stats_[streamId].resolvedAtMs = NowMs();
    }
    return res;
}

UpstreamChunkResult StreamRangeProxy::FetchHttpSocket(
    const std::string& url,
    const std::string& authHeader,
    const std::string& userAgent,
    int64_t rangeStart,
    int64_t rangeEnd,
    bool headOnly,
    int redirectDepth) {
    UpstreamChunkResult out;
    if (redirectDepth > 5) return out;

    ParsedUrl p = ParseUrl(url);
    if (!p.valid) return out;
    if (p.scheme == "https") {
        return FetchViaHttpsBridge(url, authHeader, rangeStart, rangeEnd, false);
    }

    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* res = nullptr;
    if (getaddrinfo(p.host.c_str(), p.port.c_str(), &hints, &res) != 0 || !res) {
        return out;
    }

    int sock = -1;
    for (addrinfo* rp = res; rp != nullptr; rp = rp->ai_next) {
        sock = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sock < 0) continue;
        struct timeval tv{8, 0};
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        if (connect(sock, rp->ai_addr, rp->ai_addrlen) == 0) {
            break;
        }
        close(sock);
        sock = -1;
    }
    freeaddrinfo(res);
    if (sock < 0) return out;

    std::ostringstream req;
    req << (headOnly ? "HEAD " : "GET ") << p.path << " HTTP/1.1\r\n"
        << "Host: " << p.host;
    if (p.port != "80") req << ":" << p.port;
    req << "\r\nUser-Agent: " << userAgent << "\r\n";
    if (!authHeader.empty()) {
        req << "Authorization: " << authHeader << "\r\n";
    }
    if (!headOnly && rangeStart >= 0 && rangeEnd >= rangeStart) {
        req << "Range: bytes=" << rangeStart << "-" << rangeEnd << "\r\n";
    }
    req << "Connection: close\r\n\r\n";

    if (!SendStr(sock, req.str())) {
        close(sock);
        return out;
    }

    std::vector<uint8_t> raw;
    raw.reserve(65536);
    uint8_t buf[16384];
    ssize_t headerEnd = -1;
    int64_t expectedBodyLen = -1;
    while (true) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) break;
        raw.insert(raw.end(), buf, buf + n);
        if (headerEnd < 0) {
            std::string s(reinterpret_cast<const char*>(raw.data()), raw.size());
            size_t pos = s.find("\r\n\r\n");
            if (pos != std::string::npos) {
                headerEnd = static_cast<ssize_t>(pos + 4);
                if (headOnly) break;
                // Extract Content-Length early so we don't wait for server EOF
                std::string hdrOnly = ToLower(s.substr(0, static_cast<size_t>(headerEnd)));
                size_t clPos = hdrOnly.find("\ncontent-length:");
                if (clPos != std::string::npos) {
                    size_t lineEnd = hdrOnly.find('\n', clPos + 1);
                    std::string valStr = Trim(hdrOnly.substr(clPos + 16, lineEnd == std::string::npos ? std::string::npos : lineEnd - (clPos + 16)));
                    if (!valStr.empty()) {
                        try { expectedBodyLen = std::stoll(valStr); } catch (...) {}
                    }
                }
            }
        }
        if (headerEnd >= 0) {
            int64_t bodyGot = static_cast<int64_t>(raw.size()) - headerEnd;
            if (expectedBodyLen >= 0 && bodyGot >= expectedBodyLen) {
                break;
            }
            // Guard against misbehaving servers ignoring Range on multi-GB files
            if (bodyGot >= kBlockSize * 4) {
                break;
            }
        }
    }
    close(sock);

    if (headerEnd < 0) return out;
    std::string headerStr(reinterpret_cast<const char*>(raw.data()), static_cast<size_t>(headerEnd));
    std::istringstream hiss(headerStr);
    std::string statusLine;
    std::getline(hiss, statusLine);
    {
        std::istringstream sl(statusLine);
        std::string httpVer;
        sl >> httpVer >> out.statusCode;
    }

    std::string location;
    int64_t contentLen = -1;
    std::string line;
    while (std::getline(hiss, line)) {
        std::string lower = ToLower(line);
        if (lower.rfind("location:", 0) == 0) {
            location = Trim(line.substr(9));
        } else if (lower.rfind("content-type:", 0) == 0) {
            out.contentType = Trim(line.substr(13));
        } else if (lower.rfind("content-length:", 0) == 0) {
            contentLen = std::stoll(Trim(line.substr(15)));
        } else if (lower.rfind("content-range:", 0) == 0) {
            size_t slash = line.rfind('/');
            if (slash != std::string::npos) {
                std::string totalStr = Trim(line.substr(slash + 1));
                if (totalStr != "*") {
                    out.totalSize = std::stoll(totalStr);
                }
            }
        }
    }

    if ((out.statusCode == 301 || out.statusCode == 302 || out.statusCode == 307 || out.statusCode == 308) &&
        !location.empty()) {
        // Redirects drop WebDAV Basic Auth header when going to external CDN
        UpstreamChunkResult redir = FetchHttpSocket(location, "", userAgent, rangeStart, rangeEnd, headOnly, redirectDepth + 1);
        if (redir.redirectUrl.empty()) {
            redir.redirectUrl = location;
        }
        return redir;
    }

    if (out.totalSize <= 0 && out.statusCode == 200 && contentLen > 0) {
        out.totalSize = contentLen;
    }

    if (!headOnly && static_cast<size_t>(headerEnd) < raw.size()) {
        out.data.assign(raw.begin() + headerEnd, raw.end());
    }
    return out;
}

UpstreamChunkResult StreamRangeProxy::FetchViaHttpsBridge(
    const std::string& url,
    const std::string& authHeader,
    int64_t rangeStart,
    int64_t rangeEnd,
    bool allowInsecure) {
    int64_t reqId = nextReqId_.fetch_add(1);
    std::future<UpstreamChunkResult> fut;
    HttpsFetchDispatcher dispatcherCopy;
    {
        std::lock_guard<std::mutex> lock(httpsMutex_);
        dispatcherCopy = httpsDispatcher_;
        if (!dispatcherCopy) {
            return UpstreamChunkResult{};
        }
        std::promise<UpstreamChunkResult> prom;
        fut = prom.get_future();
        pendingHttps_.emplace(reqId, std::move(prom));
    }

    dispatcherCopy(reqId, url, authHeader, rangeStart, rangeEnd, allowInsecure);
    if (fut.wait_for(std::chrono::seconds(15)) == std::future_status::ready) {
        return fut.get();
    }

    std::lock_guard<std::mutex> lock(httpsMutex_);
    pendingHttps_.erase(reqId);
    return UpstreamChunkResult{};
}

static std::string GuessVideoMime(const std::string& path) {
    std::string lower = ToLower(path);
    auto endsWith = [&](const char* ext) {
        size_t el = std::strlen(ext);
        return lower.size() >= el && lower.compare(lower.size() - el, el, ext) == 0;
    };
    if (endsWith(".mp4") || endsWith(".m4v")) return "video/mp4";
    if (endsWith(".mkv")) return "video/x-matroska";
    if (endsWith(".mov")) return "video/quicktime";
    if (endsWith(".ts") || endsWith(".m2ts")) return "video/mp2t";
    if (endsWith(".webm")) return "video/webm";
    if (endsWith(".avi")) return "video/x-msvideo";
    return "application/octet-stream";
}

UpstreamChunkResult StreamRangeProxy::FetchViaSmb(
    const std::string& streamId,
    const StreamConfig& config,
    int64_t rangeStart,
    int64_t rangeEnd,
    bool headOnly) {
    UpstreamChunkResult out;

    SmbConnectionConfig smbCfg;
    std::string relPath;
    std::string urlUser, urlPass;
    ParseSmbUrl(config.url, smbCfg.host, smbCfg.port, smbCfg.share, relPath, urlUser, urlPass);

    if (!config.smbHost.empty()) smbCfg.host = config.smbHost;
    if (config.smbPort > 0) smbCfg.port = config.smbPort;
    if (!config.smbShare.empty()) smbCfg.share = config.smbShare;
    if (!config.smbPath.empty()) relPath = config.smbPath;
    smbCfg.username = !config.smbUser.empty() ? config.smbUser : urlUser;
    smbCfg.password = !config.smbPass.empty() ? config.smbPass : urlPass;

    if (smbCfg.host.empty() || smbCfg.share.empty() || relPath.empty()) {
        return out;
    }

    std::shared_ptr<SmbOpenHandle> handle;
    {
        std::lock_guard<std::mutex> lock(smbMapMutex_);
        auto it = smbHandles_.find(streamId);
        if (it == smbHandles_.end()) {
            handle = std::make_shared<SmbOpenHandle>();
            smbHandles_[streamId] = handle;
        } else {
            handle = it->second;
        }
    }

    std::lock_guard<std::mutex> opLock(handle->opMutex);
    auto ensureOpen = [&]() -> bool {
        if (handle->session && handle->session->IsConnected() && handle->openPath == relPath && handle->fileSize >= 0) {
            return true;
        }
        handle->session = std::make_unique<Smb2Session>();
        std::string err;
        if (!handle->session->Connect(smbCfg, err)) {
            OH_LOG_ERROR(LOG_APP, "SMB connect failed: %{public}s", err.c_str());
            handle->session.reset();
            return false;
        }
        if (!handle->session->OpenFile(relPath, handle->fileId, handle->fileSize, err)) {
            OH_LOG_ERROR(LOG_APP, "SMB open failed (%{public}s): %{public}s", relPath.c_str(), err.c_str());
            handle->session.reset();
            return false;
        }
        handle->openPath = relPath;
        return true;
    };

    if (!ensureOpen()) {
        return out;
    }

    out.totalSize = handle->fileSize;
    out.contentType = GuessVideoMime(relPath);
    if (headOnly) {
        out.statusCode = 200;
        return out;
    }

    int64_t endByte = (rangeEnd >= rangeStart) ? rangeEnd : std::min(handle->fileSize - 1, rangeStart + kBlockSize - 1);
    if (rangeStart >= handle->fileSize) {
        out.statusCode = 416;
        return out;
    }
    if (endByte >= handle->fileSize) endByte = handle->fileSize - 1;
    uint32_t readLen = static_cast<uint32_t>(endByte - rangeStart + 1);

    std::string err;
    if (!handle->session->ReadFile(handle->fileId, rangeStart, readLen, out.data, err)) {
        // Reconnect once transparently on stale socket / SMB deadtime
        handle->session.reset();
        if (!ensureOpen() || !handle->session->ReadFile(handle->fileId, rangeStart, readLen, out.data, err)) {
            OH_LOG_ERROR(LOG_APP, "SMB read failed: %{public}s", err.c_str());
            return UpstreamChunkResult{};
        }
    }

    out.statusCode = 206;
    return out;
}

bool StreamRangeProxy::GetCachedBlock(const std::string& streamId, int64_t blockIndex, std::vector<uint8_t>& out) {
    std::lock_guard<std::mutex> lock(cacheMutex_);
    CacheKey key{streamId, blockIndex};
    auto it = cacheMap_.find(key);
    if (it == cacheMap_.end()) {
        return false;
    }
    lruList_.splice(lruList_.begin(), lruList_, it->second);
    out = it->second->data;
    return true;
}

void StreamRangeProxy::PutCachedBlock(const std::string& streamId, int64_t blockIndex, std::vector<uint8_t> data) {
    if (data.empty()) return;
    std::lock_guard<std::mutex> lock(cacheMutex_);
    CacheKey key{streamId, blockIndex};
    auto existing = cacheMap_.find(key);
    if (existing != cacheMap_.end()) {
        currentCacheBytes_ -= existing->second->data.size();
        existing->second->data = std::move(data);
        currentCacheBytes_ += existing->second->data.size();
        lruList_.splice(lruList_.begin(), lruList_, existing->second);
    } else {
        size_t sz = data.size();
        lruList_.push_front(CacheEntry{key, std::move(data)});
        cacheMap_[key] = lruList_.begin();
        currentCacheBytes_ += sz;
    }

    while (currentCacheBytes_ > maxCacheBytes_ && !lruList_.empty()) {
        CacheEntry& back = lruList_.back();
        currentCacheBytes_ -= back.data.size();
        cacheMap_.erase(back.key);
        lruList_.pop_back();
    }
}

void StreamRangeProxy::EvictStreamCache(const std::string& streamId) {
    std::lock_guard<std::mutex> lock(cacheMutex_);
    for (auto it = lruList_.begin(); it != lruList_.end();) {
        if (it->key.streamId == streamId) {
            currentCacheBytes_ -= it->data.size();
            cacheMap_.erase(it->key);
            it = lruList_.erase(it);
        } else {
            ++it;
        }
    }
}

} // namespace prism
