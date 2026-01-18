#!/bin/bash
set -e

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
MANIFEST_URL="$CDN_URL/hytale/manifest.json"
HYTALE_PATCHLINE=${HYTALE_PATCHLINE:-"release"}
USE_AOT_CACHE=${USE_AOT_CACHE:-"0"}
HYTALE_ALLOW_OP=${HYTALE_ALLOW_OP:-"0"}
HYTALE_AUTH_MODE=${HYTALE_AUTH_MODE:-"authenticated"}
HYTALE_ACCEPT_EARLY_PLUGINS=${HYTALE_ACCEPT_EARLY_PLUGINS:-"0"}
DISABLE_SENTRY=${DISABLE_SENTRY:-"0"}

# Create Server directory if it doesn't exist
mkdir -p Server

# Function to download file with SHA256 verification
download_file() {
    local url="$1"
    local target_path="$2"
    local expected_sha256="$3"

    if [ -f "$target_path" ]; then
        CURRENT_SHA256=$(sha256sum "$target_path" | awk '{print $1}')
        if [ "$CURRENT_SHA256" = "$expected_sha256" ]; then
            echo "$(basename "$target_path") is up to date"
            return 0
        fi
        echo "$(basename "$target_path") changed, re-downloading"
    else
        echo "$(basename "$target_path") not found, downloading"
    fi

    echo "DO NOT RESTART SERVER, FILES ARE STILL DOWNLOADING"
    # Add -k to ignore SSL verification
    curl -k -# -L -f "$url" --progress-bar -o "${target_path}.tmp"

    # Verify SHA256
    DOWNLOADED_SHA256=$(sha256sum "${target_path}.tmp" | awk '{print $1}')
    if [ "$DOWNLOADED_SHA256" != "$expected_sha256" ]; then
        echo "ERROR: SHA256 mismatch for $(basename "$target_path")"
        rm -f "${target_path}.tmp"
        exit 1
    fi

    mv "${target_path}.tmp" "$target_path"
    
}


# Fetch manifest
echo "Fetching manifest..."
curl -k -# -sSL -f "$MANIFEST_URL" -o manifest.json

LATEST_VERSION=$(jq -r '.latest_version' manifest.json)
VERSION_OBJ=$(jq -r '.versions[] | select(.version == "'$LATEST_VERSION'")' manifest.json)
DOWNLOAD_BASE=$(echo "$VERSION_OBJ" | jq -r '.download_url_base')

get_sha() {
    echo "$VERSION_OBJ" | jq -r '.files[] | select(.filename == "'$1'") | .sha256'
}

echo "Latest version: $LATEST_VERSION"
echo ""

# Download HytaleServer.jar
download_file \
  "$DOWNLOAD_BASE/Server/HytaleServer.jar" \
  "Server/HytaleServer.jar" \
  "$(get_sha 'Server/HytaleServer.jar')"
echo ""


# Download HytaleServer.aot (optional)
if [ "$USE_AOT_CACHE" = "1" ]; then
    download_file \
      "$DOWNLOAD_BASE/Server/HytaleServer.aot" \
      "Server/HytaleServer.aot" \
      "$(get_sha 'Server/HytaleServer.aot')"
    echo ""
fi

# Download Assets.zip
download_file \
  "$DOWNLOAD_BASE/Assets.zip" \
  "Assets.zip" \
  "$(get_sha 'Assets.zip')"
echo ""

# Clean up manifest
rm -f manifest.json

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
