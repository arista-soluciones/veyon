# Veyon Master for macOS

This directory contains the macOS-specific parts of the Veyon port. Together with
the `mac` platform plugin (`plugins/platform/mac`) it allows running the **teacher
side** of Veyon on a Mac:

* **Veyon Master** – monitor and control Windows/Linux computers running Veyon Service
* **Veyon Configurator** – configure Veyon (requires administrator privileges)
* **veyon-cli** – command line interface, e.g. for importing configuration and keys

Computers running macOS **cannot be monitored or controlled** yet, i.e. there is no
Veyon Service/Server for macOS (this would require screen capturing via
ScreenCaptureKit, input injection and a launchd daemon).


## Building

### Universal package (recommended)

`.ci/macos/build-universal.sh` creates a package with universal binaries which runs
on **Apple Silicon and Intel Macs with macOS 12 or newer**. It uses the official Qt
binaries (which are universal) and builds all other dependencies (OpenSSL, QCA,
libjpeg-turbo, libpng, LZO) from source into `~/veyon-deps`. LibVNCServer/Client are
built from the bundled sources, so the submodules have to be checked out.

```sh
pip install aqtinstall && aqt install-qt mac desktop 6.8.3 clang_64 -m qt5compat -O ~/Qt
brew install cmake ninja librsvg                       # build tools only

git submodule update --init 3rdparty/libvncserver
QT_ROOT_DIR=~/Qt/6.8.3/macos .ci/macos/build-universal.sh . /tmp/build-macos dist
```

The GitHub Actions workflow `.github/workflows/macos.yml` does the same on every push,
installs and tests the package on an Intel and an Apple Silicon Mac, and provides it
as the build artifact `veyon-master-macos-universal`.

### Package using Homebrew libraries

For development, `.ci/macos/build.sh` builds against the libraries from
[Homebrew](https://brew.sh):

```sh
brew install cmake ninja pkgconf openssl@3 libvncserver librsvg
brew install qtbase qttools qt5compat qttranslations   # or: brew install qt
brew install qca

.ci/macos/build.sh . /tmp/build-macos dist
```

Homebrew only provides its libraries for Apple Silicon and the macOS versions it
currently supports, so such a package requires an Apple Silicon Mac with at least the
macOS version of the build machine.

Both scripts configure and build Veyon, assemble the application bundles, deploy Qt and
all other libraries into them via `macdeployqt`, sign them ad-hoc and create
`dist/veyon-master-<version>-macos-<architectures>.pkg`.

Notes:

* Server components (`WITH_SERVER`) and the LDAP plugin (`WITH_LDAP`) are disabled
  by default on macOS.
* Set `CODESIGN_IDENTITY` (Developer ID Application) and `INSTALLER_SIGN_IDENTITY`
  (Developer ID Installer) when running `create-package.sh` to create signed
  packages which can subsequently be notarized with `xcrun notarytool`.


## Installation layout

| Path | Content |
|---|---|
| `/Applications/Veyon/Veyon Master.app` | Veyon Master (also contains `veyon-cli` and `veyon-configurator`) |
| `/Applications/Veyon/Veyon Configurator.app` | Veyon Configurator |
| `/usr/local/bin/veyon-cli` | wrapper script for `veyon-cli` |
| `/Library/Preferences/com.veyon-solutions.Veyon.plist` | system-wide configuration |
| `/Library/Application Support/Veyon/keys` | authentication keys |
| `~/Library/Application Support/Veyon` | per-user data (e.g. screenshots) |


## Installing and configuring a teacher Mac

1. **Install the package.** The package is not signed by Apple yet, so a package
   downloaded with a web browser is blocked by Gatekeeper. Either install it from a
   terminal

   ```sh
   sudo installer -pkg veyon-master-*.pkg -target /
   ```

   or open it via *System Settings → Privacy & Security → Open Anyway*.

2. **Import the configuration** used on the other computers. Export it on an
   existing Veyon installation (*Veyon Configurator → File → Save settings to file*
   or `veyon-cli config export veyon.json`) and import it on the Mac:

   ```sh
   sudo veyon-cli config import veyon.json
   ```

   Configurations exported on Windows may contain Windows-specific paths. Check
   e.g. `veyon-cli config get Authentication/PrivateKeyBaseDir` and reset such
   values with `sudo veyon-cli config unset <key>` to use the macOS defaults.

3. **Import the teacher's private key** (when using key file authentication) and
   restrict access to it to the group of teacher accounts (`staff` = all local
   users):

   ```sh
   sudo veyon-cli authkeys import teacher/private teacher_private_key.pem
   sudo veyon-cli authkeys setaccessgroup teacher/private staff
   ```

4. **Start Veyon Master** and confirm the *Local Network* access prompt (macOS 15
   and newer). If access was denied, all computers appear offline – re-enable it in
   *System Settings → Privacy & Security → Local Network*.

Alternatively start *Veyon Configurator*, which asks for administrator credentials
and offers the full configuration UI.

If Veyon Configurator reports that the configuration is not writable, start it
from Terminal with administrator privileges instead:

```sh
sudo "/Applications/Veyon/Veyon Configurator.app/Contents/MacOS/veyon-configurator"
```


## Known limitations

* Demo mode cannot broadcast the screen of the Mac itself (no local Veyon Server).
* Computers running macOS can't be accessed (see above).
* System keyboard shortcuts (e.g. Cmd+Tab) are not forwarded during remote control.
  Cmd is sent as Ctrl to make shortcuts like Cmd+C work as expected on the remote
  computer; Ctrl+Del sends Ctrl+Alt+Del.
