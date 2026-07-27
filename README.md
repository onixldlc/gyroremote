# GyroRemote — build via Podman

## Layout
```
.
├── Dockerfile          # builder image (Temurin 17 + Android SDK 34 + Gradle 8.7)
├── build.sh            # runs inside the container as `build`
├── README.md
├── build/              # APK drops here (created by the build, gitignored)
├── keystore/           # persistent debug signing key (created by the build, gitignored)
└── project/            # the Gradle root (settings.gradle.kts lives here)
    ├── app/
    └── gradle/wrapper/
```

## One-time: build the image
```bash
podman build -t app-builder .
```

## Every build
```bash
podman run --rm -v "$PWD:/workspace:z" app-builder
```

One mount, that's it. The APK is written to `/workspace/build` inside the
container, which is `./build` on the host. `:z` relabels for SELinux — needed on
Fedora/RHEL, harmless elsewhere.

`build.sh` locates the Gradle root by searching `/workspace` (up to 3 levels) for
`settings.gradle.kts`, so it finds `project/` on its own. To pin it explicitly:

```bash
podman run --rm -e PROJECT_DIR=project -v "$PWD:/workspace:z" app-builder
```

You can also mount the Gradle root directly with `-v "$PWD/project:/workspace:z"`
— the APK then lands in `project/build/`.

## Install on the phone

Over USB:
```bash
adb install -r build/app-debug.apk
```

Or sideload over the network — serve the APK and download it on the device:
```bash
cd build && python3 -m http.server 8000
```
Browse to `http://<host-ip>:8000/app-debug.apk` from the phone. Android 8+ asks
for "Install unknown apps" permission for whichever browser did the download;
grant it once. Same wifi required.

## Notes
- Gradle 8.7 is baked into the image, so no Gradle download at build time. What
  *is* downloaded on first run is the AGP/Kotlin dependency set into
  `GRADLE_USER_HOME`. Persist it across runs with a cache volume — measured
  ~1m05s cold vs ~12s warm:
  ```bash
  podman run --rm \
    -v "$PWD:/workspace:z" \
    -v gradle-cache:/opt/gradle-cache \
    app-builder
  ```
- The mount must be writable: Gradle writes `project/app/build/` and
  `project/.gradle/` into the source tree, the APK into `build/`, and the debug
  signing key into `keystore/`. All are gitignored.
- **Debug signing key persists in `./keystore`.** `build.sh` symlinks the
  container's `$HOME/.android` to `/workspace/keystore`, so the key survives
  `--rm`. Without this every build would sign with a fresh key and the phone
  would reject each reinstall with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Delete
  `keystore/` and you get a new identity — uninstall the app from the phone
  first. To use your host key instead, bind-mount over it and `build.sh` will
  step aside: `-v "$HOME/.android:/root/.android:z"`. Details in
  `android-debug-signing.md`.
- The project ships `project/gradle/wrapper/gradle-wrapper.properties` but no
  `gradlew` script or wrapper jar, so `build.sh` falls back to the image's
  `gradle` binary — the wrapper properties are ignored on that path. Both pin
  8.7, so versions match. To get a real wrapper, run `gradle wrapper` once
  inside `project/`.
