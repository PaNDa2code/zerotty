#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Initialize an associative array to track downloaded URLs and prevent infinite loops
declare -A VISITED_URLS

# Ask Zig where its global cache is located
ZIG_CACHE_DIR=$(zig env | grep '"global_cache_dir"' | cut -d '"' -f 4)
ZIG_P_DIR="$ZIG_CACHE_DIR/p"

fetch_deps() {
    local zon_file="$1"

    # Base case: if there is no zon file, exit the function
    if [[ ! -f "$zon_file" ]]; then
        return 0
    fi

    # Extract all http/https URLs from .url fields
    # The `|| true` prevents the script from crashing if a package has no URLs
    local urls
    urls=$(grep -oE '\.url\s*=\s*"https?://[^"]+"' "$zon_file" | grep -oE 'https?://[^"]+' || true)

    for url in $urls; do
        # Check if we have already fetched this specific URL
        if [[ -z "${VISITED_URLS[$url]:-}" ]]; then
            VISITED_URLS["$url"]=1
            echo "Fetching: $url"

            # Create a temporary file ending in .tar.gz (forces Zig to parse it as an archive)
            local tmp_archive
            tmp_archive=$(mktemp --suffix=.tar.gz)

            # 1. Download via curl (handles redirects and query strings perfectly)
            if curl -sSL "$url" -o "$tmp_archive"; then
                
                # 2. Feed the local file to `zig fetch`. 
                # Zig will extract it into the global cache and print the content hash.
                local hash
                hash=$(zig fetch "$tmp_archive" 2>/dev/null || true)

                if [[ -n "$hash" ]]; then
                    echo "  -> Cached as $hash"
                    local child_zon="$ZIG_P_DIR/$hash/build.zig.zon"
                    
                    # 3. Recursively parse the newly downloaded dependency
                    fetch_deps "$child_zon"
                else
                    echo "  -> Error: Zig failed to unpack the archive"
                fi
            else
                echo "  -> Error: curl failed to download the URL"
            fi

            # Clean up the temp file
            rm -f "$tmp_archive"
        fi
    done
}

# Ensure we are running this in a directory with a build.zig.zon
if [[ ! -f "build.zig.zon" ]]; then
    echo "Error: build.zig.zon not found in the current directory."
    exit 1
fi

echo "Starting recursive dependency fetch..."
fetch_deps "build.zig.zon"
echo "Done!"


