#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace prism {

struct SmbConnectionConfig {
    std::string host;
    int port = 445;
    std::string share;
    std::string domain;
    std::string username;
    std::string password;
};

struct SmbFileEntry {
    std::string name;
    std::string path;      // POSIX path inside share e.g. "/rw/download/movie/foo.mp4"
    bool isDirectory = false;
    int64_t size = 0;
    int64_t lastModifiedMs = 0;
};

struct SmbListResult {
    bool ok = false;
    std::string error;
    std::vector<SmbFileEntry> entries;
};

class Smb2Session {
public:
    Smb2Session() = default;
    ~Smb2Session();

    Smb2Session(const Smb2Session&) = delete;
    Smb2Session& operator=(const Smb2Session&) = delete;

    bool Connect(const SmbConnectionConfig& config, std::string& errOut);
    void Disconnect();
    bool IsConnected() const { return sockFd_ >= 0 && treeConnected_; }

    SmbListResult ListDirectory(const std::string& shareRelDir);

    bool OpenFile(const std::string& shareRelPath, uint8_t outFileId[16], int64_t& outFileSize, std::string& errOut);
    bool ReadFile(const uint8_t fileId[16], int64_t offset, uint32_t length, std::vector<uint8_t>& outData, std::string& errOut);
    void CloseFile(const uint8_t fileId[16]);

    // Convenience helper to read a whole small file (e.g., .nfo / .srt / .ass) up to maxBytes
    bool ReadSmallFile(const std::string& shareRelPath, size_t maxBytes, std::vector<uint8_t>& outData, std::string& errOut);

private:
    bool SendSmb2Packet(uint16_t command,
                        uint16_t creditCharge,
                        uint32_t treeId,
                        const std::vector<uint8_t>& body,
                        uint32_t& outStatus,
                        std::vector<uint8_t>& outHeader,
                        std::vector<uint8_t>& outBody,
                        std::string& errOut);

    bool DoNegotiate(std::string& errOut);
    bool DoSessionSetup(const SmbConnectionConfig& config, std::string& errOut);
    bool DoTreeConnect(const SmbConnectionConfig& config, std::string& errOut);

    int sockFd_ = -1;
    uint64_t messageId_ = 0;
    uint64_t sessionId_ = 0;
    uint32_t treeId_ = 0;
    uint32_t maxReadSize_ = 65536;
    bool treeConnected_ = false;
};

// Parses smb://[user[:pass]@]host[:port]/share[/subpath] cleanly
bool ParseSmbUrl(const std::string& url,
                 std::string& outHost,
                 int& outPort,
                 std::string& outShare,
                 std::string& outRelPath,
                 std::string& outUser,
                 std::string& outPass);

} // namespace prism
