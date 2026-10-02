// Little-endian byte helpers shared by the protocol codec. Platform independent.
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace spooldry {

class ByteWriter {
public:
    ByteWriter(uint8_t* buf, size_t cap) : buf_(buf), cap_(cap) {}
    void u8(uint8_t v) { put(&v, 1); }
    void u16(uint16_t v) {
        uint8_t b[2] = {static_cast<uint8_t>(v & 0xFF), static_cast<uint8_t>(v >> 8)};
        put(b, 2);
    }
    void i16(int16_t v) { u16(static_cast<uint16_t>(v)); }
    void u32(uint32_t v) {
        uint8_t b[4] = {static_cast<uint8_t>(v & 0xFF), static_cast<uint8_t>((v >> 8) & 0xFF),
                        static_cast<uint8_t>((v >> 16) & 0xFF), static_cast<uint8_t>((v >> 24) & 0xFF)};
        put(b, 4);
    }
    void bytes(const uint8_t* p, size_t n) { put(p, n); }
    size_t size() const { return len_; }
    bool overflowed() const { return overflow_; }

private:
    void put(const uint8_t* p, size_t n) {
        if (len_ + n > cap_) {
            overflow_ = true;
            return;
        }
        for (size_t i = 0; i < n; ++i) buf_[len_ + i] = p[i];
        len_ += n;
    }
    uint8_t* buf_;
    size_t cap_;
    size_t len_ = 0;
    bool overflow_ = false;
};

class ByteReader {
public:
    ByteReader(const uint8_t* buf, size_t len) : buf_(buf), len_(len) {}
    bool u8(uint8_t& v) {
        if (pos_ + 1 > len_) return false;
        v = buf_[pos_++];
        return true;
    }
    bool u16(uint16_t& v) {
        if (pos_ + 2 > len_) return false;
        v = static_cast<uint16_t>(buf_[pos_] | (buf_[pos_ + 1] << 8));
        pos_ += 2;
        return true;
    }
    bool i16(int16_t& v) {
        uint16_t u;
        if (!u16(u)) return false;
        v = static_cast<int16_t>(u);
        return true;
    }
    bool u32(uint32_t& v) {
        if (pos_ + 4 > len_) return false;
        v = static_cast<uint32_t>(buf_[pos_]) | (static_cast<uint32_t>(buf_[pos_ + 1]) << 8) |
            (static_cast<uint32_t>(buf_[pos_ + 2]) << 16) | (static_cast<uint32_t>(buf_[pos_ + 3]) << 24);
        pos_ += 4;
        return true;
    }
    size_t remaining() const { return len_ - pos_; }

private:
    const uint8_t* buf_;
    size_t len_;
    size_t pos_ = 0;
};

}  // namespace spooldry
