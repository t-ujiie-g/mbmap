// A command line over Esri's LEPCC C API for bench/lepcc: encodes seeded points, colors and
// intensities, and decodes blobs as lepcc_getBlobInfo + lepcc_get*Count + lepcc_decode* do.
// Built by bench/lepcc/upstream.mjs; all numbers little-endian, on stdin and stdout (flushed per
// record, so the records before a sanitizer's abort are kept).
//   cli xyz <maxXErr> <maxYErr> <maxZErr>   in: f64 x, y, z per point; out: u32 n, blob, u32 order[points]
//   cli rgb                                 in: u8 r, g, b per point;  out: u32 n, blob
//   cli intensity                           in: u16 per point;         out: u32 n, blob
//   cli decode                              in: records of u32 kind (0 xyz, 1 rgb, 2 intensity), u32 n, blob
// For each decoded record: i32 info status, u32 info type, u32 info size, i32 count status, u32 count,
// i32 decode status (-1 past 0x400000 points, not decoded), u32 decoded count, u32 unfilled points,
// then the values.
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>
#include "include/lepcc_c_api.h"

static std::vector<unsigned char> readAll(FILE* f) {
  std::vector<unsigned char> out;
  unsigned char buf[65536];
  size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.insert(out.end(), buf, buf + n);
  return out;
}

static void put32(unsigned int v) { fwrite(&v, 4, 1, stdout); }

static int fail(const char* what, unsigned int status) {
  fprintf(stderr, "%s failed: %u\n", what, status);
  return 1;
}

static int encode(int argc, char** argv) {
  std::vector<unsigned char> in = readAll(stdin);
  lepcc_ContextHdl ctx = lepcc_createContext();
  unsigned int size = 0;
  lepcc_status s;
  std::vector<unsigned int> order;
  if (!strcmp(argv[1], "xyz")) {
    if (argc < 5) return fail("arguments", 0);
    unsigned int n = (unsigned int)(in.size() / 24);
    order.resize(n);
    s = lepcc_computeCompressedSizeXYZ(ctx, n, (const double*)in.data(), atof(argv[2]), atof(argv[3]), atof(argv[4]), &size, order.data());
  } else if (!strcmp(argv[1], "rgb")) {
    s = lepcc_computeCompressedSizeRGB(ctx, (unsigned int)(in.size() / 3), in.data(), &size);
  } else {
    s = lepcc_computeCompressedSizeIntensity(ctx, (unsigned int)(in.size() / 2), (const unsigned short*)in.data(), &size);
  }
  if (s) return fail("computeCompressedSize", s);
  std::vector<unsigned char> blob(size);
  unsigned char* p = blob.data();
  if (!strcmp(argv[1], "xyz")) s = lepcc_encodeXYZ(ctx, &p, (int)size);
  else if (!strcmp(argv[1], "rgb")) s = lepcc_encodeRGB(ctx, &p, (int)size);
  else s = lepcc_encodeIntensity(ctx, &p, (int)size, (const unsigned short*)in.data(), (unsigned int)(in.size() / 2));
  if (s) return fail("encode", s);
  unsigned int written = (unsigned int)(p - blob.data());
  put32(written);
  fwrite(blob.data(), 1, written, stdout);
  if (!order.empty()) fwrite(order.data(), 4, order.size(), stdout);
  lepcc_deleteContext(&ctx);
  return 0;
}

static int decode() {
  std::vector<unsigned char> in = readAll(stdin);
  lepcc_ContextHdl ctx = lepcc_createContext();
  size_t at = 0;
  while (at + 8 <= in.size()) {
    unsigned int kind, n;
    memcpy(&kind, &in[at], 4);
    memcpy(&n, &in[at + 4], 4);
    at += 8;
    if (at + n > in.size()) return fail("record", 0);
    // Each blob in a buffer of its own size, so reads past it are the sanitizer's to catch.
    std::vector<unsigned char> blob(in.begin() + at, in.begin() + at + n);
    at += n;
    const unsigned char* data = blob.empty() ? nullptr : blob.data();
    lepcc_blobType type = 0;
    unsigned int blobSize = 0, count = 0, decoded = 0, unfilled = 0;
    lepcc_status info = data ? lepcc_getBlobInfo(ctx, data, (int)n, &type, &blobSize) : 2;
    lepcc_status cs = data ? (kind == 0 ? lepcc_getPointCount : kind == 1 ? lepcc_getRGBCount : lepcc_getIntensityCount)(ctx, data, (int)n, &count) : 2;
    lepcc_status ds = 1;
    std::vector<unsigned char> out;
    // Past mbmap's MAX_POINTS the port refuses; such counts are only reported.
    if (!cs && count > 0x400000) ds = 0xffffffffu;
    else if (!cs && data) {
      const unsigned char* p = data;
      decoded = count;
      if (kind == 0) {
        std::vector<double> xyz((size_t)count * 3);
        memset(xyz.data(), 0xff, xyz.size() * 8);
        ds = lepcc_decodeXYZ(ctx, &p, (int)n, &decoded, xyz.data());
        unsigned long long sentinel = ~0ull;
        for (unsigned int i = 0; i < decoded && i < count; i++)
          if (!memcmp(&xyz[i * 3], &sentinel, 8)) unfilled++;
        out.assign((unsigned char*)xyz.data(), (unsigned char*)xyz.data() + xyz.size() * 8);
      } else if (kind == 1) {
        out.resize((size_t)count * 3);
        ds = lepcc_decodeRGB(ctx, &p, (int)n, &decoded, out.data());
      } else {
        std::vector<unsigned short> v(count);
        ds = lepcc_decodeIntensity(ctx, &p, (int)n, &decoded, v.data());
        out.assign((unsigned char*)v.data(), (unsigned char*)v.data() + v.size() * 2);
      }
    }
    put32(info);
    put32(type);
    put32(blobSize);
    put32(cs);
    put32(count);
    put32(ds);
    put32(ds ? 0 : decoded);
    put32(unfilled);
    if (!ds) {
      size_t each = kind == 0 ? 24 : kind == 1 ? 3 : 2;
      fwrite(out.data(), 1, (size_t)decoded * each, stdout);
    }
    fflush(stdout);
  }
  lepcc_deleteContext(&ctx);
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 2) return fail("usage", 0);
  if (!strcmp(argv[1], "decode")) return decode();
  return encode(argc, argv);
}
