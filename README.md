# macEyes
A macOS menu bar adaptation of the classic Unix `xeyes` — a pair of eyes that follow your mouse cursor, right in your menu bar.

## Installation

### Requirements
- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

### Build from source

```bash
git clone git@github.com:SN0371/maceyes.git
cd maceyes
swift build -c release
```

### Run

```bash
.build/release/maceyes &
```

The eyes will appear in your menu bar immediately. Click them to access the menu, or press **Q** to quit.

### Run at login (optional)

Copy the binary to a permanent location and add it to your login items:

```bash
cp .build/release/maceyes /usr/local/bin/maceyes
```

Then go to **System Settings → General → Login Items** and add the `maceyes` binary.
