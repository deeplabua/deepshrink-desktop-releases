# FFmpeg in DeepShrink for the Mac App Store

The Mac App Store version of DeepShrink ships `ffmpeg` and `ffprobe` as separate helper
programs (`DeepShrink.app/Contents/MacOS/ffmpeg`, `…/ffprobe`). They are **FFmpeg 9.0.2,
licensed under the GNU Lesser General Public License v2.1 or later**, built without any GPL,
version-3 or non-free component. DeepShrink runs them as separate processes and does not link
to them.

- **Exact build:** [`BUILDINFO.txt`](BUILDINFO.txt) lists every source tarball and FFmpeg's
  `configure` line.
- **Build script:** [`build-ffmpeg-lgpl.sh`](build-ffmpeg-lgpl.sh) rebuilds both binaries from
  those sources (macOS 13+, Apple silicon, Xcode command-line tools, Homebrew `cmake meson ninja
  nasm pkg-config autoconf automake libtool`).
- **Complete corresponding sources:** the
  [`ffmpeg-lgpl-9.0.2` release](https://github.com/deeplabua/deepshrink-desktop-releases/releases/tag/ffmpeg-lgpl-9.0.2)
  holds the original tarballs of FFmpeg and every library in it, the script and `SHA256SUMS`.

To use your own build, replace `ffmpeg` and `ffprobe` inside `DeepShrink.app/Contents/MacOS/`
with binaries built by the script (re-signing the app is then up to you).

Components: FFmpeg (LGPL-2.1-or-later), LAME (LGPL-2.0-or-later), Opus, libogg, libvorbis
(BSD-3-Clause), SVT-AV1 (BSD-3-Clause-Clear + AOM patent licence), dav1d (BSD-2-Clause), libvmaf
(BSD-2-Clause-Patent), zimg (WTFPL). Apple's VideoToolbox and AudioToolbox are system frameworks.

The DeepShrink version from deeplab.tools (DMG) ships a different FFmpeg build; see the app's
Help → Acknowledgements.
