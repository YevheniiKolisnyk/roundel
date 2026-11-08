# Architecture notes

A short map of the parts that are not obvious from the folder names. `CLAUDE.md` (local) has the working rules.

## Images

- **Reading** is always ImageIO (`ImageIOSource`), for every format including WebP. libwebp is used for *writing* WebP only,
  and its decoder is never linked (`scripts/check-webp-decoder.sh`).
- **Writing** goes through `ImageBackends` (ImageIO first, libwebp for WebP). `image.convert` changes the format;
  `image.compress` keeps it.
- **Compress** (`Images/Compress/`): `CompressionPlan` decides per file from `ImageFacts` (pure, tested), `ImageCompressor`
  runs a batch: type by content, hidden temporary file next to the source, keep the result only if it saves at least
  `ImageCompressor.minimumSaving` (2%), move into place without replacing anything. `OutputPlacer` (name reservation, temp
  file, move) and `BatchRunner` + `ConcurrencyPlan` (three at a time, but at most 50 megapixels in flight; a bigger image
  runs alone) are shared with `ImageConverter`.
- **PNG** is not re-encoded by ImageIO (its PNG writer makes files bigger). `PNGOptimizer` works on the file's chunks:
  inflate the image data, optionally store it in a smaller equivalent way (only when provably lossless, and never when the
  file has chunks whose meaning depends on the sample format), pick the best row filters, deflate again, keep every other
  chunk. The result is verified against the pixels before it is returned.
- **Test tools:** `TestPNG` (an independent PNG writer and reader) and `TestImages` (generated pictures, SSIM, PSNR) live in
  the test target; the compression presets are held to similarity floors there, not at run time.

## System zlib

The PNG optimizer needs deflate with a chosen level and strategy. Apple's Compression framework offers one fixed level, so the
package declares a system library target, `CZlib` (`Sources/CZlib`, a module map over `<zlib.h>`, linked with `-lz`). zlib
ships with macOS; nothing is downloaded, built or bundled, so it is not listed in `THIRD_PARTY_LICENSES.md`.
