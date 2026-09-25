# Redmi Note 9 5G root handoff

## Verified on this phone

- Model `M2007J22C`, codename `cannon` (China Redmi Note 9 5G), Android 12, MIUI `V14.0.6.0.SJECNXM`.
- Bootloader currently locked (`ro.boot.flash.locked=1`); verified boot is green.
- This is **not** the global `merlin` variant. Never use a `merlin` image or a patched image supplied by someone else.
- The readable shared storage has been copied to `.data/backup/sdcard` on this Mac (3,710 files, about 782 MiB). ADB cannot back up private app data, account credentials, or app specific storage. Check those backups on the phone before unlocking.
- The official Xiaomi Mi Unlock package is at `.data/miflash_unlock-en-6.5.224.28.zip`. It includes x64 Windows drivers. The available Mac is Apple Silicon, so use the x64 Windows computer you said you can borrow.

## Before pressing Unlock

1. Check that photos, chats, authenticator codes, app data, and account recovery methods are backed up separately. Confirm you can sign back in to the phone's Mi account after a wipe.
2. On the phone, enable OEM unlocking and bind the same Mi account in **Developer options → Mi Unlock status**. Xiaomi may impose an account binding wait; keep the account on the device and follow the tool's exact time shown. A valid SIM and mobile data may be required by Xiaomi's flow.
3. On x64 Windows, extract the downloaded Mi Unlock ZIP, install its drivers, sign in with the same Mi account, and connect the phone in Fastboot mode (power off, then Volume Down + Power). Verify that the tool identifies this device before pressing Unlock. Unlocking erases user data.
4. After unlocking and initial setup, re-enable USB debugging, reconnect to this Mac, and confirm `fastboot getvar unlocked` or the phone's Mi Unlock status says unlocked.

Xiaomi's [bootloader FAQ](https://www.mi.com/sg/support/faq/details/KA-07238/) describes account binding, waiting, and data erasure. Do not use an unofficial bypass or relock while modified images are installed.

## Matching stock image and Magisk

Run `./scripts/prepare-firmware.sh` on the Mac. It resumes the official `cannon` fastboot firmware download, verifies the catalog MD5 `ce9fc0ac4876041df59fa098a400da36`, and extracts only candidate boot, init_boot, recovery, and vbmeta images. The archive is 5.49 GB; the download may take time. A partial `.tgz` is not verified and must not be flashed.

Install Magisk from its [official release](https://github.com/topjohnwu/Magisk/releases) **on this same phone**. The [Magisk installation guide](https://topjohnwu.github.io/Magisk/install.html) says to check whether Magisk reports a boot ramdisk, choose boot/init_boot or recovery accordingly, select and patch the matching stock image on the phone, then pull the generated `magisk_patched_*.img` with ADB. Confirm the actual Fastboot partition layout before flashing; retain the verified stock image for recovery. Flash only after the bootloader is unlocked and the image's MIUI build still matches the phone. If MIUI changes, download and verify the new matching firmware first.

After flashing, verify that the phone boots, Magisk reports installed, ADB works, and AI Passport reconnects. If boot fails, use the verified stock image for the same partition with Fastboot; use the full official firmware recovery process if that does not work. Do not relock a modified phone.

Root is intentionally pending: the x64 Windows machine is not connected here, the account wait is unknown, the private app data backup has not been confirmed, and the 5.49 GB firmware has not yet passed its full MD5 check.
