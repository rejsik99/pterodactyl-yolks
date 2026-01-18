#!/bin/bash

# Hytale Server Entrypoint

TZ=${TZ:-UTC}
export TZ

INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

cd /home/container || exit 1

# Set default values
SERVER_PORT=${SERVER_PORT:-"5520"}
MAXIMUM_RAM=${MAXIMUM_RAM:-"90"}
JVM_FLAGS=${JVM_FLAGS:-""}
CDN_URL=${CDN_URL:-"https://api.nodezy.gg"}
HYTALE_PATCHLINE=${HYTALE_PATCHLINE:-"release"}
USE_AOT_CACHE=${USE_AOT_CACHE:-"0"}
HYTALE_ALLOW_OP=${HYTALE_ALLOW_OP:-"0"}
HYTALE_AUTH_MODE=${HYTALE_AUTH_MODE:-"authenticated"}
HYTALE_ACCEPT_EARLY_PLUGINS=${HYTALE_ACCEPT_EARLY_PLUGINS:-"0"}
DISABLE_SENTRY=${DISABLE_SENTRY:-"0"}

# Create Server directory if it doesn't exist
mkdir -p Server

# Function to download file (no verification)
download_file() {
    local filename=$1
    local target_path=$2

    echo "Downloading $filename..."
    if ! curl -# -L -f "$CDN_URL/hytale/latest/$filename" -o "${target_path}.tmp"; then
        echo "ERROR: Failed to download $filename"
        rm -f "${target_path}.tmp"
        return 1
    fi

    mv "${target_path}.tmp" "$target_path"
    return 0
}

echo "Downloading server files..."

# Download HytaleServer.jar
if ! download_file "Server/HytaleServer.jar" "Server/HytaleServer.jar"; then
    echo "ERROR: Failed to download HytaleServer.jar"
    exit 1
fi
echo ""

# Download HytaleServer.aot (optional)
if [ "$USE_AOT_CACHE" = "1" ]; then
    download_file "Server/HytaleServer.aot" "Server/HytaleServer.aot"
    echo ""
fi

# Download Assets.zip
if ! download_file "Assets.zip" "Assets.zip"; then
    echo "ERROR: Failed to download Assets.zip"
    exit 1
fi
echo ""

# Verify server jar exists
if [ ! -f "Server/HytaleServer.jar" ]; then
    echo "ERROR: Server JAR not found after download"
    exit 1
fi

echo "All files downloaded successfully"
echo ""

# Calculate memory
SERVER_MEMORY_REAL=$((SERVER_MEMORY * MAXIMUM_RAM / 100))

# Build startup command
STARTUP_CMD="java"

# Add AOT cache if enabled and file exists
if [ "$USE_AOT_CACHE" = "1" ] && [ -f "Server/HytaleServer.aot" ]; then
    STARTUP_CMD+=" -XX:AOTCache=Server/HytaleServer.aot"
fi

# Add memory settings
STARTUP_CMD+=" -Xms128M -Xmx${SERVER_MEMORY_REAL}M"

# Add custom JVM flags
[ -n "$JVM_FLAGS" ] && STARTUP_CMD+=" $JVM_FLAGS"

# Add jar
STARTUP_CMD+=" -jar Server/HytaleServer.jar"

# Optional flags
[ "$HYTALE_ALLOW_OP" = "1" ] && STARTUP_CMD+=" --allow-op"
[ "$HYTALE_ACCEPT_EARLY_PLUGINS" = "1" ] && STARTUP_CMD+=" --accept-early-plugins"
[ "$DISABLE_SENTRY" = "1" ] && STARTUP_CMD+=" --disable-sentry"

# Required arguments
STARTUP_CMD+=" --auth-mode $HYTALE_AUTH_MODE"
STARTUP_CMD+=" --assets Assets.zip"
STARTUP_CMD+=" --bind 0.0.0.0:$SERVER_PORT"

echo "Starting Hytale Server v$LATEST_VERSION"
echo "$STARTUP_CMD"
echo ""

exec $STARTUP_CMD
