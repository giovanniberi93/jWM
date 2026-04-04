#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <input.mov> -o <output.gif>"
    exit 1
}

[[ $# -lt 3 ]] && usage
input="$1"
[[ "$2" != "-o" ]] && usage
output="$3"

[[ ! -f "$input" ]] && echo "Error: $input not found" && exit 1

ffmpeg -y -i "$input" \
    -vf "fps=10,scale=1200:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=none" \
    -loop 0 "$output"

gifsicle -O3 "$output" -o "$output"
