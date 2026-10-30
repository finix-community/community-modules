{ lib, python3 }:

python3.pkgs.buildPythonApplication {
  pname = "steam-apply";
  version = "0.1.0";
  format = "other";

  src = ./.;

  installPhase = ''
    runHook preInstall
    install -Dm755 steam_apply.py $out/bin/steam-apply
    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    HOME=$TMPDIR python3 -m unittest -v test_steam_apply
    runHook postCheck
  '';

  meta = {
    description = "Merge declarative per-app settings into Steam's config files";
    license = lib.licenses.mit;
    mainProgram = "steam-apply";
    platforms = lib.platforms.linux;
  };
}
