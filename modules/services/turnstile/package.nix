{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  scdoc,
  meson,
  ninja,
  pam,
  dinit,
  graphicalMonitor ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "turnstile";
  version = "v0.1.11";

  src = fetchFromGitHub {
    owner = "chimera-linux";
    repo = "turnstile";
    rev = "${finalAttrs.version}";
    sha256 = "sha256-94J+w0RHxzw7wS70LcpEzMvgevAqAwl0EtiANUmdRYU=";
  };

  buildInputs = [
    pkg-config
    scdoc
    meson
    ninja
    pam
    dinit
  ];

  # nativeBuildInputs = [
  #   dinit
  # ];

  postPatch = lib.strings.concatStrings [
    (lib.strings.optionalString graphicalMonitor ''
      substituteInPlace backend/dinit \
        --replace-fail '/usr/bin/dinit-monitor' '${lib.getExe' dinit "dinit-monitor"}'
    '')

    ''
      substituteInPlace meson.build \
        --replace-fail "get_option('prefix'), get_option('sysconfdir'), 'turnstile'" "'/etc', 'turnstile'"
    ''
  ];

  mesonFlags = [
    "-Ddefault_backend=dinit"
    "-Ddinit=enabled"
    "-Dstatedir=/var/lib/turnstiled"
    "-Dpam_moddir=./pam"
  ];

  patches = lib.lists.optional (!graphicalMonitor) (./remove_graphical_monitor.diff);

  meta = with lib; {
    homepage = "https://github.com/chimera-linux/turnstile";
    description = "This program waits for user logins and then runs the associated user-service manager";
    license = licenses.bsd2;
    maintainers = with maintainers; [ vitrial ];
    platforms = platforms.linux;
    mainProgram = "turnstiled";
  };

})
