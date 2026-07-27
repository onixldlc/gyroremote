# Android APK builder — no Android Studio, just cmdline SDK + Gradle
FROM eclipse-temurin:17-jdk-jammy

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/opt/gradle-cache \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

ARG CMDLINE_TOOLS_VERSION=11076708
# ANDROID_PLATFORM / BUILD_TOOLS_VERSION must match the project's compileSdk.
# Verified working set: android-34 + 34.0.0 + Gradle 8.7 + AGP 8.5.2 + Kotlin 1.9.24.
ARG ANDROID_PLATFORM=android-34
ARG BUILD_TOOLS_VERSION=34.0.0
ARG GRADLE_VERSION=8.7

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Gradle (used as fallback when project has no gradlew)
RUN curl -fsSL -o /tmp/gradle.zip \
      https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip

RUN unzip -q /tmp/gradle.zip -d /opt && rm /tmp/gradle.zip

RUN ln -s /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle

# Fail the image build here rather than on someone's first project build
RUN gradle --version

# Install Android command-line tools
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools

RUN curl -fsSL -o /tmp/cmdline.zip \
      https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip

RUN unzip -q /tmp/cmdline.zip -d ${ANDROID_HOME}/cmdline-tools && rm /tmp/cmdline.zip

RUN mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest

# Accept licenses, then install required SDK packages.
# stdout is dropped because sdkmanager streams megabytes of \r progress bars;
# stderr is left alone, so real failures still surface in the build log.
RUN yes | sdkmanager --licenses > /dev/null

RUN sdkmanager \
      "platform-tools" \
      "platforms;${ANDROID_PLATFORM}" \
      "build-tools;${BUILD_TOOLS_VERSION}" > /dev/null

# Assert the packages actually landed — sdkmanager can exit 0 having installed nothing
RUN test -d ${ANDROID_HOME}/platforms/${ANDROID_PLATFORM}
RUN test -x ${ANDROID_HOME}/build-tools/${BUILD_TOOLS_VERSION}/aapt2

# Gradle writes its dependency cache here. Pre-create it world-writable so the
# image still works when run with a non-root UID (rootless podman, --user).
RUN mkdir -p ${GRADLE_USER_HOME} && chmod 777 ${GRADLE_USER_HOME}

WORKDIR /workspace

COPY build.sh /usr/local/bin/build

RUN chmod +x /usr/local/bin/build

# Gradle itself is baked in at /opt/gradle-${GRADLE_VERSION}; only the dependency
# cache under GRADLE_USER_HOME warms on first real build (~1 min for this project).

ENTRYPOINT []
CMD ["build"]
