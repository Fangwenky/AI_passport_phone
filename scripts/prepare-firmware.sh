#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
firmware_dir="$project_dir/.data/firmware"
archive_name='cannon_images_V14.0.6.0.SJECNXM_20231017.0000.00_12.0_cn_ce9fc0ac48.tgz'
archive="$firmware_dir/$archive_name"
expected_md5='ce9fc0ac4876041df59fa098a400da36'
url="https://cdnorg.d.miui.com/V14.0.6.0.SJECNXM/$archive_name"

mkdir -p "$firmware_dir"
actual_md5=''
if [[ -f "$archive" ]]; then actual_md5="$(md5 -q "$archive")"; fi
if [[ "$actual_md5" != "$expected_md5" ]]; then
  curl --fail --location --retry 3 --continue-at - --silent --show-error --output "$archive" "$url"
  actual_md5="$(md5 -q "$archive")"
fi
if [[ "$actual_md5" != "$expected_md5" ]]; then
  printf 'MD5 mismatch: expected %s, got %s\n' "$expected_md5" "$actual_md5" >&2
  exit 1
fi

python3 - "$archive" "$firmware_dir" <<'PY'
import pathlib
import sys
import tarfile

archive, output = sys.argv[1], pathlib.Path(sys.argv[2])
wanted = {'boot.img', 'init_boot.img', 'recovery.img', 'vbmeta.img'}
with tarfile.open(archive, 'r:gz') as package:
    for item in package:
        if not item.isfile() or pathlib.PurePosixPath(item.name).name not in wanted:
            continue
        if '/images/' not in f'/{item.name}':
            continue
        destination = output / pathlib.PurePosixPath(item.name).name
        source = package.extractfile(item)
        if source is None:
            continue
        with source, destination.open('wb') as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
        print(f'{destination.name}: {destination.stat().st_size} bytes')
print('Firmware verified and candidate images extracted. Do not flash before checking Magisk ramdisk and partition layout.')
PY
printf 'MD5 %s  %s\n' "$actual_md5" "$archive_name" > "$firmware_dir/VERIFIED.txt"
