#!/usr/bin/env bash
# LGPL ffmpeg / ffprobe for the Mac App Store build (session 019b).
#
#   desktop/scripts/build-ffmpeg-lgpl.sh            # → src-tauri/binaries-mas/{ffmpeg,ffprobe}-aarch64-apple-darwin
#
# The DMG ships osxexperts' static `--enable-gpl` build (x264 / x265). GPL code
# can't go to the App Store, so the store build gets this one instead:
#   - FFmpeg under LGPL-2.1-or-later: no --enable-gpl / --enable-version3 / --enable-nonfree;
#   - H.264 / HEVC through Apple's VideoToolbox (the core's hardware path), AAC
#     with FFmpeg's own encoder, AV1 with SVT-AV1, MP3 with LAME, Opus, Vorbis;
#   - dav1d (AV1 decode), libvmaf (Compare's VMAF), zimg (`zscale` HDR → SDR);
#   - static, arm64 only (VideoToolbox's constant quality is Apple Silicon only),
#     macOS 13+, no network, nothing autodetected from Homebrew.
# Every library is permissive (BSD / WTFPL) except LAME (LGPL); the exact sources
# and configure line are written to `BUILDINFO.txt` next to the binaries (LGPL:
# users must be able to rebuild and relink — the Acknowledgements link to it).
#
# Built once per version set, cached in $DS_FFMPEG_CACHE (default
# ~/Library/Caches/deepshrink/ffmpeg-lgpl). Needs: cmake, meson, ninja, nasm,
# pkg-config, autotools, Xcode command-line tools.
set -euo pipefail

FFMPEG_VERSION=9.0.2
OPUS_VERSION=1.5.2
LAME_VERSION=3.100
OGG_VERSION=1.3.6
VORBIS_VERSION=1.3.7
SVTAV1_VERSION=4.2.0
DAV1D_VERSION=1.5.4
VMAF_VERSION=3.0.0
ZIMG_VERSION=3.0.5

ROOT="$(cd "$(dirname "$0")/.." && pwd)"           # desktop/
OUT="$ROOT/src-tauri/binaries-mas"
TRIPLE=aarch64-apple-darwin
KEY="ff$FFMPEG_VERSION-opus$OPUS_VERSION-lame$LAME_VERSION-ogg$OGG_VERSION-vorbis$VORBIS_VERSION-svt$SVTAV1_VERSION-dav1d$DAV1D_VERSION-vmaf$VMAF_VERSION-zimg$ZIMG_VERSION"
CACHE="${DS_FFMPEG_CACHE:-$HOME/Library/Caches/deepshrink/ffmpeg-lgpl}/$KEY"
SRC="$CACHE/src"
PREFIX="$CACHE/prefix"
JOBS="$(sysctl -n hw.ncpu)"

# Apple Silicon Homebrew tools first (a stale Intel /usr/local autotools breaks zimg's autogen).
export PATH="/opt/homebrew/bin:$PATH"
export LIBTOOLIZE=glibtoolize
export MACOSX_DEPLOYMENT_TARGET=13.0
export CFLAGS="-arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
# Only our own prefix — never Homebrew's .pc files.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""

install_out() {
  mkdir -p "$OUT"
  cp "$PREFIX/bin/ffmpeg" "$OUT/ffmpeg-$TRIPLE"
  cp "$PREFIX/bin/ffprobe" "$OUT/ffprobe-$TRIPLE"
  cp "$CACHE/BUILDINFO.txt" "$OUT/BUILDINFO.txt"
  echo "LGPL ffmpeg → $OUT"
}

if [[ -x "$PREFIX/bin/ffmpeg" && -f "$CACHE/BUILDINFO.txt" ]]; then
  install_out
  exit 0
fi

mkdir -p "$SRC" "$PREFIX"
fetch() { # url dir
  local url=$1 dir=$2
  [[ -d "$SRC/$dir" ]] && return
  echo "↓ $url"
  mkdir -p "$SRC/$dir"
  curl -fsSL "$url" | tar -xf - -C "$SRC/$dir" --strip-components 1
}

fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" opus
fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" lame
fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.xz" ogg
fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.xz" vorbis
fetch "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.gz" svtav1
fetch "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz" dav1d
fetch "https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz" vmaf
fetch "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$ZIMG_VERSION.tar.gz" zimg
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" ffmpeg

autotools() { # dir [configure args…]
  local dir=$1; shift
  [[ -f "$SRC/$dir/.installed" ]] && return
  (cd "$SRC/$dir" && ./configure --prefix="$PREFIX" --host=aarch64-apple-darwin \
    --enable-static --disable-shared "$@" && make -j"$JOBS" && make install && touch .installed)
}

autotools opus --disable-doc --disable-extra-programs
autotools lame --disable-frontend --disable-decoder
autotools ogg
# libvorbis 1.3.7's configure adds `-force_cpusubtype_ALL`, which the current linker rejects.
sed -i '' 's/ -force_cpusubtype_ALL//g' "$SRC/vorbis/configure"
autotools vorbis --with-ogg="$PREFIX"
(cd "$SRC/zimg" && ./autogen.sh)
autotools zimg

cmake -S "$SRC/svtav1" -B "$SRC/svtav1/build" -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
cmake --build "$SRC/svtav1/build" && cmake --install "$SRC/svtav1/build"

meson_build() { # dir [meson args…]
  local dir=$1; shift
  rm -rf "$SRC/$dir/build"
  meson setup "$SRC/$dir/build" "$SRC/$dir" --prefix="$PREFIX" --libdir=lib \
    --buildtype=release --default-library=static "$@"
  ninja -C "$SRC/$dir/build" && ninja -C "$SRC/$dir/build" install
}
meson_build dav1d -Denable_tools=false -Denable_tests=false
# libvmaf lives in the repo's libvmaf/ folder; models are compiled in.
rm -rf "$SRC/vmaf/build"
meson setup "$SRC/vmaf/build" "$SRC/vmaf/libvmaf" --prefix="$PREFIX" --libdir=lib \
  --buildtype=release --default-library=static \
  -Denable_tests=false -Denable_docs=false -Dbuilt_in_models=true -Denable_float=true
ninja -C "$SRC/vmaf/build" && ninja -C "$SRC/vmaf/build" install

FFMPEG_CONFIGURE=(
  --prefix="$PREFIX"
  --arch=arm64 --target-os=darwin --enable-cross-compile
  --cc=clang --cxx=clang++
  --pkg-config-flags=--static
  --enable-static --disable-shared
  --disable-autodetect
  --disable-network --disable-doc --disable-ffplay --disable-debug
  --enable-videotoolbox --enable-audiotoolbox --enable-zlib
  --enable-libsvtav1 --enable-libdav1d --enable-libvmaf --enable-libzimg
  --enable-libopus --enable-libmp3lame --enable-libvorbis
  --extra-cflags="$CFLAGS -I$PREFIX/include"
  --extra-ldflags="$LDFLAGS -L$PREFIX/lib"
  --extra-libs="-lc++"
)
(cd "$SRC/ffmpeg" && ./configure "${FFMPEG_CONFIGURE[@]}" && make -j"$JOBS" && make install)

# The licence check is part of the build: it must say LGPL and nothing GPL.
"$PREFIX/bin/ffmpeg" -hide_banner -L | head -4 | tr '\n' ' ' | grep -q "GNU Lesser General Public License" \
  || { echo "ffmpeg is not LGPL"; exit 1; }
if "$PREFIX/bin/ffmpeg" -hide_banner -buildconf | grep -qE -- "--enable-(gpl|nonfree|version3)"; then
  echo "ffmpeg was configured with a GPL / nonfree / v3 option"; exit 1
fi
otool -L "$PREFIX/bin/ffmpeg" | grep -E "/opt/homebrew|/usr/local" && { echo "links Homebrew libs"; exit 1; }

{
  echo "FFmpeg $FFMPEG_VERSION — LGPL-2.1-or-later build for DeepShrink (Mac App Store)."
  echo "Rebuild: desktop/scripts/build-ffmpeg-lgpl.sh (sources below, then the configure line)."
  echo
  echo "Sources:"
  echo "  FFmpeg   $FFMPEG_VERSION  https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz  (LGPL-2.1-or-later)"
  echo "  Opus     $OPUS_VERSION  https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz  (BSD-3-Clause)"
  echo "  LAME     $LAME_VERSION  https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz  (LGPL-2.0-or-later)"
  echo "  libogg   $OGG_VERSION  https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.xz  (BSD-3-Clause)"
  echo "  libvorbis $VORBIS_VERSION  https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.xz  (BSD-3-Clause)"
  echo "  SVT-AV1  $SVTAV1_VERSION  https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.gz  (BSD-3-Clause-Clear + AOM patent licence)"
  echo "  dav1d    $DAV1D_VERSION  https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz  (BSD-2-Clause)"
  echo "  libvmaf  $VMAF_VERSION  https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz  (BSD-2-Clause-Patent)"
  echo "  zimg     $ZIMG_VERSION  https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$ZIMG_VERSION.tar.gz  (WTFPL)"
  echo
  echo "FFmpeg configure:"
  printf '  %s\n' "${FFMPEG_CONFIGURE[@]}" | sed "s|$PREFIX|<prefix>|g"
} > "$CACHE/BUILDINFO.txt"

install_out
