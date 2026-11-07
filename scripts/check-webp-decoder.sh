#!/bin/bash
# Security check: libwebp's decoder must not be part of the app.
#
# Roundel uses libwebp only to WRITE WebP. Reading WebP is ImageIO's job. libwebp's decoding code (the kind of code
# behind CVE-2023-4863) must therefore never be called; the linker then drops it, so it is absent from the release
# binary. This script builds the release binary and fails if any libwebp decoder symbol is in it, or if the binary is
# stripped/lacks libwebp's encoder (then the check would prove nothing).
#
# Usage: scripts/check-webp-decoder.sh        (run after changing anything in Sources/RoundelWebP or the libwebp version)
set -euo pipefail
cd "$(dirname "$0")/.."

build_log="$(mktemp)"
if ! swift build -c release >"$build_log" 2>&1; then cat "$build_log" >&2; rm -f "$build_log"; echo "FAIL: release build failed" >&2; exit 2; fi
rm -f "$build_log"
binary="$(swift build -c release --show-bin-path)/Roundel"
[ -f "$binary" ] || { echo "FAIL: no release binary at $binary" >&2; exit 2; }

symbols="$(nm -a "$binary" 2>/dev/null || true)"

# Control: the encoder must be visible, or this check cannot see anything.
if ! grep -qE " [tT] _WebPEncode$" <<<"$symbols"; then
  echo "FAIL: libwebp's encoder is not visible in $binary (stripped binary, or libwebp is not linked): cannot verify" >&2
  exit 2
fi

decoder='WebPDecode|WebPDecodeRGBA|WebPDecodeBGRA|WebPGetInfo|WebPGetFeaturesInternal|WebPInitDecoderConfigInternal|WebPIDecode|WebPINewDecoder|VP8GetHeaders|VP8Decode|VP8LDecodeImage|VP8LDecodeHeader|VP8LBuildHuffmanTable|WebPAnimDecoderNewInternal|WebPDemuxInternal'
found="$(grep -E " [tT] _($decoder)$" <<<"$symbols" || true)"
if [ -n "$found" ]; then
  echo "FAIL: libwebp decoder code is in the app:" >&2
  echo "$found" >&2
  echo "Only ImageIO may read WebP. Remove the call to libwebp's decoder." >&2
  exit 1
fi
echo "OK: libwebp's encoder is linked and none of its decoder is ($binary)"
