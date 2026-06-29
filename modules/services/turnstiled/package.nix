{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  graphicalMonitor ? true,
}:

stdenv.mkDerivation {
  pname = "turnstiled";
  version = "0-unstable-2025-12-15";

  src = fetchFromGitHub {
    owner = "chimera-linux";
    repo = "turnstile";
    rev = "e3413dad386bf72048646f9f9ffd3a8d60e10eb0";
    sha256 = "sha256-TH0zLYKgDup+byBxr68R3DWt1/+BFJIkXWSuqSHAEOE=";
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    scdoc
    meson
    ninja
    pam
  ];

  buildInputs = with pkgs; [
    dinit
  ];

  mesonFlags = [
    "-Ddefault_backend=dinit"
    "-Ddinit=enabled"
    "-Dstatedir=/var/lib/turnstiled"
    "-Dpam_moddir=./pam"
  ];

  patches = [
    ./patch.diff
  ]
  ++ lib.lists.optional (!graphicalMonitor) (./remove_graphical_monitor.diff);

  doInstallCheck = false;

  meta = with lib; {
    homepage = "https://github.com/chimera-linux/turnstile";
    description = "This program waits for user logins and then runs the associated user-service manager";
    license = licenses.bsd2;
    maintainers = with maintainers; [ vitrial ];
    platforms = platforms.linux;
    mainProgram = "turnstiled";
  };

}
