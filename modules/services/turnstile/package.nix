{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  scdoc,
  meson,
  ninja,
  pam,
  dinitSupport ? true,
  dinit,
  runitSupport ? true,
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

  nativeBuildInputs = [
    pkg-config
    scdoc
    meson
    ninja
  ];

  buildInputs = [
    pam
  ];

  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail "get_option('prefix'), get_option('sysconfdir'), 'turnstile'" "'/etc', 'turnstile'"
  ''
  + lib.optionalString dinitSupport ''
    substituteInPlace backend/dinit \
      --replace-fail '/usr/bin/dinit-monitor' '${lib.getExe' dinit "dinit-monitor"}'
  '';

  mesonFlags = [
    "-Dlocalstatedir=/var"
    "-Dpam_moddir=${placeholder "out"}/lib/security"
    (lib.mesonEnable "dinit" dinitSupport)
    (lib.mesonEnable "runit" runitSupport)
  ];

  meta = with lib; {
    homepage = "https://github.com/chimera-linux/turnstile";
    description = "This program waits for user logins and then runs the associated user-service manager";
    license = licenses.bsd2;
    maintainers = with maintainers; [ vitrial ];
    platforms = platforms.linux;
    mainProgram = "turnstiled";
  };

})
