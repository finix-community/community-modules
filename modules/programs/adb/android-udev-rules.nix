{
  lib,
  stdenv,
  fetchFromGitHub,
  udevCheckHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "android-udev-rules";
  version = "20260922";

  src = fetchFromGitHub {
    owner = "M0Rf30";
    repo = "android-udev-rules";
    rev = finalAttrs.version;
    hash = "sha256-eEMCPkYp0GlBXcd+WhojITqSHzGhj7uB6GR7SYuyArg=";
  };

  installPhase = ''
    runHook preInstall
    install -D 51-android.rules $out/lib/udev/rules.d/51-android.rules
    runHook postInstall
  '';

  nativeBuildInputs = [
    udevCheckHook
  ];
  doInstallCheck = true;

  meta = {
    homepage = "https://github.com/M0Rf30/android-udev-rules";
    description = "Android udev rules list aimed to be the most comprehensive on the net";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
    maintainers = [ ];
    teams = [ lib.teams.android ];
  };
})
