{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  gobject-introspection,
  wrapGAppsHook3,
  gtk3,
  makeWrapper,
  gnutar,
  gzip,
  procps,
  util-linux,
}:
let
  # the interactive viewer is a gtk 3 application driven through pygobject
  python = python3.withPackages (ps: [
    ps.pycairo
    ps.pygobject3
  ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "initviz";
  version = "1.0.0-rc1";

  src = fetchFromGitHub {
    owner = "finit-project";
    repo = "InitViz";
    rev = "b18898a2405db96a14036948f6bb3ef17b9303bf";
    hash = "sha256-rwgzp2PITN4dHatctS+vgVuZm/ojR3XyOOYVYFht3CA=";
  };

  patches = [
    # https://github.com/finit-project/InitViz/issues/3
    ./collector-chroot-skeleton-nonfatal.patch

    # https://github.com/finit-project/InitViz/pull/2
    ./bootchartd-wait-boot-noop-without-exit-proc.patch
  ];

  nativeBuildInputs = [
    python
    gobject-introspection
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    gtk3
    python
  ];

  postPatch = ''
    substituteInPlace Makefile --replace-fail '$(DESTDIR)/etc/' '$(DESTDIR)$(EARLY_PREFIX)/etc/'
  '';

  makeFlags = [
    "PYTHON=${python.interpreter}"
    "EARLY_PREFIX=${placeholder "out"}"
    "BINDIR=${placeholder "out"}/bin"
    "PKGLIBDIR=${placeholder "out"}/lib/bootchart"
    "LIBDIR=/lib"
    "DOCDIR=${placeholder "out"}/share/doc/initviz"
    "MANDIR=${placeholder "out"}/share/man/man1"
    "PY_LIBDIR=${placeholder "out"}/${python3.sitePackages}"
    "PY_SITEDIR=${placeholder "out"}/${python3.sitePackages}"
    "NO_PYTHON_COMPILE=1"
  ];

  postInstall = ''
    # initviz.__version__ reads ../VERSION relative to the package directory
    install -m 644 VERSION "$out/${python3.sitePackages}/VERSION"

    wrapProgram "$out/sbin/bootchartd" \
      --prefix PATH : ${
        lib.makeBinPath [
          gnutar
          gzip
          procps
          util-linux
        ]
      }
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PYTHONPATH : "$out/${python3.sitePackages}")
  '';

  meta = {
    description = "Boot and init process performance visualization tool";
    homepage = "https://github.com/finit-project/InitViz";
    license = lib.licenses.gpl3Plus;
    mainProgram = "initviz";
    platforms = lib.platforms.linux;
  };
})
