#!/usr/bin/env bash
# Build the debug APK and drop it in <mount>/build, i.e. ./build on the host.
set -euo pipefail

MOUNT=/workspace
OUT="$MOUNT/build"

if [ ! -d "$MOUNT" ] || [ -z "$(ls -A "$MOUNT" 2>/dev/null)" ]; then
  echo "ERROR: /workspace is empty. Mount your project at /workspace." >&2
  echo "  e.g. podman run -v \"\$PWD:/workspace:z\" app-builder" >&2
  exit 1
fi

# The Gradle root is wherever settings.gradle[.kts] lives — the repo root, or a
# subdir like project/. PROJECT_DIR overrides the search.
if [ -n "${PROJECT_DIR:-}" ]; then
  SRC="$MOUNT/$PROJECT_DIR"
  if [ ! -f "$SRC/settings.gradle.kts" ] && [ ! -f "$SRC/settings.gradle" ]; then
    echo "ERROR: PROJECT_DIR=$PROJECT_DIR has no settings.gradle[.kts]." >&2
    exit 1
  fi
elif [ -f "$MOUNT/settings.gradle.kts" ] || [ -f "$MOUNT/settings.gradle" ]; then
  SRC="$MOUNT"
else
  # -H: follow $MOUNT itself if it is a symlink, but don't chase symlinks below it
  FOUND=$(find -H "$MOUNT" -maxdepth 3 \( -name settings.gradle.kts -o -name settings.gradle \) \
            -not -path '*/build/*' -printf '%h\n' 2>/dev/null | sort -u)
  if [ "$(printf '%s\n' "$FOUND" | grep -c .)" -gt 1 ]; then
    echo "WARNING: multiple Gradle roots found, using the first:" >&2
    printf '  %s\n' $FOUND >&2
    echo "  Set PROJECT_DIR to pick one explicitly." >&2
  fi
  SRC=$(printf '%s\n' "$FOUND" | head -n1)
fi

if [ -z "${SRC:-}" ] || [ ! -d "$SRC" ]; then
  echo "ERROR: no settings.gradle.kts found under $MOUNT (searched 3 levels deep)." >&2
  echo "  Set PROJECT_DIR to the Gradle root relative to /workspace, e.g. -e PROJECT_DIR=project" >&2
  exit 1
fi

# Gradle writes app/build/ and .gradle/ into the source tree, and the finished
# APK goes to $OUT — both live inside the mount, so it must be writable. Fail
# here with a clear message instead of deep inside Gradle.
for dir in "$MOUNT" "$SRC"; do
  if [ ! -w "$dir" ]; then
    echo "ERROR: $dir is not writable, but the build needs to write there." >&2
    echo "  On SELinux hosts, mount with :z — e.g. -v \"\$PWD:/workspace:z\"" >&2
    exit 1
  fi
done

mkdir -p "$OUT"

# --- persistent debug keystore ------------------------------------------------
# AGP generates its debug signing key at $HOME/.android/debug.keystore. In a
# --rm container that dies with the container, so every build would sign with a
# fresh key and the phone would reject every reinstall with
# INSTALL_FAILED_UPDATE_INCOMPATIBLE. Point $HOME/.android at the mount so the
# key (and adb keys, etc.) survive on the host in ./keystore.
KEYSTORE="$MOUNT/keystore"
ANDROID_CFG="${HOME:-/root}/.android"

mkdir -p "$KEYSTORE"

if grep -qs " $ANDROID_CFG " /proc/mounts; then
  # Someone bind-mounted their own .android — respect it, don't clobber.
  echo ">> $ANDROID_CFG is a mount, leaving it alone (./keystore unused)"
elif [ -L "$ANDROID_CFG" ]; then
  rm -f "$ANDROID_CFG"                       # stale link from a previous run
  ln -s "$KEYSTORE" "$ANDROID_CFG"
else
  if [ -d "$ANDROID_CFG" ]; then
    cp -an "$ANDROID_CFG/." "$KEYSTORE/" 2>/dev/null || true   # keep image defaults
    rm -rf "$ANDROID_CFG"
  fi
  mkdir -p "$(dirname "$ANDROID_CFG")"
  ln -s "$KEYSTORE" "$ANDROID_CFG"
fi

if [ -f "$KEYSTORE/debug.keystore" ]; then
  echo ">> debug keystore: reusing ./keystore/debug.keystore"
else
  echo ">> debug keystore: none yet, Gradle will create ./keystore/debug.keystore"
fi

cd "$SRC"

echo ">> Gradle root: $SRC"
echo ">> $(java -version 2>&1 | head -n1)"
echo ">> ANDROID_HOME=${ANDROID_HOME:-unset}"

# Make gradlew executable in case the host lost the bit
[ -f ./gradlew ] && chmod +x ./gradlew

echo ">> Building debug APK..."
if [ -f ./gradlew ]; then
  ./gradlew --no-daemon assembleDebug
else
  gradle --no-daemon assembleDebug
fi

APK=$(find app/build/outputs/apk/debug -name '*.apk' 2>/dev/null | head -n1)
if [ -z "$APK" ]; then
  echo "ERROR: build reported success but no APK found under" >&2
  echo "  $SRC/app/build/outputs/apk/debug" >&2
  echo "  Is the application module named something other than :app?" >&2
  exit 1
fi

cp "$APK" "$OUT/"
echo ">> APK copied to $OUT/$(basename "$APK")  (host: ./build/$(basename "$APK"))"
ls -lh "$OUT"
