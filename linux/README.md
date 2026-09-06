# Linux release notes

Moment Linux targets Ubuntu 22.04 or newer on x86_64 and is distributed as an
AppImage. Build on Ubuntu 22.04 to keep the glibc baseline compatible with all
supported releases.

Install the build dependencies before building:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev \
  liblzma-dev ffmpeg pulseaudio-utils
```

`ffmpeg` and `pulseaudio-utils` are only needed for recording. Playback codecs
are bundled in the AppImage. API keys require a running Secret Service such as
GNOME Keyring; Moment never stores them as plaintext.

Build and package:

```bash
flutter pub get
flutter build linux --release
tool/package_linux_appimage.sh
```

The generated file is `dist/Moment-<version>-x86_64.AppImage`. If FUSE is not
available, start it with `--appimage-extract-and-run`.
