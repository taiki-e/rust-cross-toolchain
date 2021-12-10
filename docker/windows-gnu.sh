#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

case "${RUST_TARGET}" in
    x86_64-*) ;;
    i686-*)
        # Adapted from https://github.com/rust-embedded/cross/blob/16a64e7028d90a3fdf285cfd642cdde9443c0645/docker/mingw.sh
        # Ubuntu mingw packages for i686 uses sjlj exceptions, but rust target
        # i686-pc-windows-gnu uses dwarf exceptions. So we build mingw packages
        # that are compatible with rust.
        mkdir -p /tmp/gcc-mingw-src
        cd /tmp/gcc-mingw-src
        apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 source gcc-mingw-w64-i686
        apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 build-dep -y gcc-mingw-w64-i686
        cd gcc-mingw-w64-*
        # We are using dwarf exceptions instead of sjlj
        sed -i -e 's/libgcc_s_sjlj-1/libgcc_s_dw2-1/g' debian/gcc-mingw-w64-i686.install
        # Only build i686 packages (disable x86_64)
        patch -p1 <<'EOF'
diff --git a/debian/control.template b/debian/control.template
index 5c80a28..eb85d4b 100644
--- a/debian/control.template
+++ b/debian/control.template
@@ -1,7 +1,6 @@
 Package: @@PACKAGE@@-mingw-w64
 Architecture: all
 Depends: @@PACKAGE@@-mingw-w64-i686,
-         @@PACKAGE@@-mingw-w64-x86-64,
          ${misc:Depends}
 Recommends: @@RECOMMENDS@@
 Built-Using: gcc-@@VERSION@@ (= ${gcc:Version})
@@ -32,22 +31,3 @@ Description: GNU @@LANGUAGE@@ compiler for MinGW-w64 targeting Win32
  This package contains the @@LANGUAGE@@ compiler, supporting
  cross-compiling to 32-bit MinGW-w64 targets.
 Build-Profiles: <!stage1>
-
-Package: @@PACKAGE@@-mingw-w64-x86-64
-Architecture: any
-Depends: @@DEPENDS64@@,
-         ${misc:Depends},
-         ${shlibs:Depends}
-Suggests: gcc-@@VERSION@@-locales (>= ${local:Version})
-Breaks: @@BREAKS64@@
-Conflicts: @@CONFLICTS64@@
-Replaces: @@REPLACES64@@
-Built-Using: gcc-@@VERSION@@ (= ${gcc:Version})
-Description: GNU @@LANGUAGE@@ compiler for MinGW-w64 targeting Win64
- MinGW-w64 provides a development and runtime environment for 32- and
- 64-bit (x86 and x64) Windows applications using the Windows API and
- the GNU Compiler Collection (gcc).
- .
- This package contains the @@LANGUAGE@@ compiler, supporting
- cross-compiling to 64-bit MinGW-w64 targets.
-Build-Profiles: <!stage1>
EOF

        # Disable build of fortran,objc,obj-c++ and use configure options
        # --disable-sjlj-exceptions --with-dwarf2
        patch -p1 <<'EOF'
diff --git a/debian/rules b/debian/rules
index 63718b8..742e35c 100755
--- a/debian/rules
+++ b/debian/rules
@@ -58,7 +58,7 @@ ifneq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
     INSTALL_TARGET := install-gcc
 else
 # Build the full GCC.
-    languages := c,c++,fortran,objc,obj-c++,ada
+    languages := c,c++
     BUILD_TARGET :=
     INSTALL_TARGET := install install-lto-plugin
 endif
@@ -85,7 +85,7 @@ control-stamp:
 	sed -i 's/@@VERSION@@/$(target_version)/g' debian/control
 	touch $@

-targets := i686-w64-mingw32 x86_64-w64-mingw32
+targets := i686-w64-mingw32
 threads := posix win32

 # Hardening on the host, none on the target
@@ -216,6 +216,10 @@ CONFFLAGS += \
 # Enable libatomic
 CONFFLAGS += \
 	--enable-libatomic
+# Enable dwarf exceptions
+CONFFLAGS += \
+	--disable-sjlj-exceptions \
+	--with-dwarf2
 # Enable experimental::filesystem and std::filesystem
 CONFFLAGS += \
 	--enable-libstdcxx-filesystem-ts=yes
EOF

        dpkg-buildpackage -B -us -uc -nc -j"$(nproc)" &>build.log || (cat build.log && exit 1)

        rm /tmp/toolchain/g*-mingw-w64-i686*.deb /tmp/toolchain/gcc-mingw-w64-base*.deb
        mv ../g*-mingw-w64-i686*.deb ../gcc-mingw-w64-base*.deb /tmp/toolchain
        ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
