FROM ubuntu:22.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install required packages and dependencies
RUN apt-get update && apt-get install -y \
	cmake \
	expect \
	git \
	ninja-build \
	python3 \
	unzip \
	wget \
	xz-utils \
	default-jre \
	&& rm -rf /var/lib/apt/lists/*

# Create a non-root user and set up the working directory
RUN useradd -m -s /bin/bash gbemu
USER gbemu
WORKDIR /home/gbemu

# Install Tizen Studio CLI and configure the toolchain path
RUN wget -nv -O web-cli_Tizen_Studio_6.1_ubuntu-64.bin 'https://download.tizen.org/sdk/Installer/tizen-studio_6.1/web-cli_Tizen_Studio_6.1_ubuntu-64.bin'
RUN chmod a+x web-cli_Tizen_Studio_6.1_ubuntu-64.bin
RUN ./web-cli_Tizen_Studio_6.1_ubuntu-64.bin --accept-license --no-java-check /home/gbemu/tizen-studio
ENV PATH=/home/gbemu/tizen-studio/tools/ide/bin:/home/gbemu/tizen-studio/tools:${PATH}

# Prepare the Tizen certificate and security profiles for signing the application package
RUN tizen certificate \
	-a gbemu \
	-f gbemu \
	-p 1234
RUN tizen security-profiles add \
	-n gbemu \
	-a /home/gbemu/tizen-studio-data/keystore/author/gbemu.p12 \
	-p 1234

# Workaround to package applications without gnome-keyring
RUN sed -i 's|/home/gbemu/tizen-studio-data/keystore/author/gbemu.pwd||' /home/gbemu/tizen-studio-data/profile/profiles.xml
RUN sed -i 's|/home/gbemu/tizen-studio-data/tools/certificate-generator/certificates/distributor/tizen-distributor-signer.pwd|tizenpkcs12passfordsigner|' /home/gbemu/tizen-studio-data/profile/profiles.xml

# Install official Emscripten SDK
RUN git clone https://github.com/emscripten-core/emsdk.git /home/gbemu/emsdk
WORKDIR /home/gbemu/emsdk

RUN ./emsdk install latest
RUN ./emsdk activate latest
RUN echo 'source /home/gbemu/emsdk/emsdk_env.sh' >> /home/gbemu/.bashrc

# Copy the GB-EMU_Tizen source into the image
# NOTE: build this Dockerfile from the root of your local GB-EMU_Tizen checkout
WORKDIR /home/gbemu
COPY --chown=gbemu . ./gb-emu-tizen

# Build gb-emu using Emscripten (CMakeLists.txt lives at repo root, no submodules)
WORKDIR /home/gbemu/gb-emu-tizen

# The repo ships a committed build/ dir with a CMakeCache.txt baked to the
# original author's machine path - it must be removed or CMake refuses to
# reconfigure in this container.
RUN rm -rf build

RUN bash -lc "source /home/gbemu/emsdk/emsdk_env.sh && \
    emcmake cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -G Ninja \
        -S . \
        -B build"

RUN bash -lc "source /home/gbemu/emsdk/emsdk_env.sh && \
    emmake ninja -C build"

# ------------------------------------------------------------------
# GB-EMU_Tizen ships NO Tizen widget wrapper (no config.xml/icon).
# We assemble a minimal one here ourselves.
# ------------------------------------------------------------------
WORKDIR /home/gbemu
RUN mkdir -p widget

# Emscripten's target has SUFFIX .html -> gb-emu.html/.js/.wasm
RUN cp gb-emu-tizen/build/gb-emu.html widget/index.html
RUN cp gb-emu-tizen/build/gb-emu.js   widget/
RUN cp gb-emu-tizen/build/gb-emu.wasm widget/

# Optional: ship the bundled example ROM so it's available for manual loading/testing
RUN mkdir -p widget/roms && cp gb-emu-tizen/roms/examples.gb widget/roms/ 2>/dev/null || true

# Minimal Tizen widget config (adjust app id / name / privileges as needed)
RUN cat > widget/config.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<widget xmlns="http://www.w3.org/ns/widgets"
        xmlns:tizen="http://tizen.org/ns/widgets"
        id="GbEmuTzn01.GBEmu"
        version="1.0.0"
        viewmodes="maximized">
    <tizen:application id="GbEmuTzn01.GBEmu"
                        package="GbEmuTzn01"
                        required_version="6.0"/>
    <content src="index.html"/>
    <feature name="http://tizen.org/feature/screen.size.all"/>
    <icon src="icon.svg"/>
    <name>GBEmu</name>
    <tizen:profile name="tv-samsung"/>
    <tizen:metadata key="http://samsung.com/tv/metadata/use.dialog" value="true"/>
</widget>
EOF

# Minimal placeholder icon (swap this out for something nicer)
RUN cat > widget/icon.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
  <rect width="128" height="128" rx="16" fill="#8b8b8b"/>
  <rect x="24" y="16" width="80" height="96" rx="8" fill="#c0c0c0"/>
  <rect x="34" y="26" width="60" height="44" fill="#9bbc0f"/>
  <circle cx="64" cy="92" r="10" fill="#333"/>
</svg>
EOF

# Sign and package the application into a WGT file
RUN echo \
	'set timeout -1\n' \
	'spawn tizen package -t wgt -- widget\n' \
	'expect "Author password:"\n' \
	'send -- "1234\\r"\n' \
	'expect "Yes: (Y), No: (N) ?"\n' \
	'send -- "N\\r"\n' \
	'expect eof\n' \
| expect

RUN mv widget/GBEmu.wgt .

# Clean up unnecessary files to reduce image size
RUN rm -rf \
	widget \
	gb-emu-tizen \
	web-cli_Tizen_Studio_6.1_ubuntu-64.bin \
	tizen-package-expect.sh \
	.package-manager \
	emsdk \
	.wget-hsts

# Use a multi-stage build to reclaim space from deleted files
FROM ubuntu:22.04
COPY --from=base /home/gbemu/GBEmu.wgt /home/gbemu/GBEmu.wgt
COPY --from=base /home/gbemu/tizen-studio /home/gbemu/tizen-studio
COPY --from=base /home/gbemu/tizen-studio-data /home/gbemu/tizen-studio-data

RUN useradd -m -s /bin/bash gbemu
RUN chown -R gbemu:gbemu /home/gbemu

USER gbemu
WORKDIR /home/gbemu

# Add Tizen Studio tools to PATH environment variable
ENV PATH=/home/gbemu/tizen-studio/tools/ide/bin:/home/gbemu/tizen-studio/tools:${PATH}
