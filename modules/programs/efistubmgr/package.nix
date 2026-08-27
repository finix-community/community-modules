{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "efistubmgr";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "FixeQD";
    repo = "${finalAttrs.pname}";
    tag = "v${finalAttrs.version}";
    hash = "sha256-37x8XovrC5uijGuCfS8zmSqR8ltSHVgedWmTmTC62JM=";
  };

  cargoHash = "sha256-uTd5K8wvtoplZfc+328bquTyAIdcHCVYF8ljgtcx2No=";

  meta = {
    description = "Minimal EFISTUB manager written in Rust.";
    homepage = "https://github.com/${finalAttrs.src.owner}/${finalAttrs.pname}/";
    license = lib.licenses.gpl3Only;
    maintainers = [ "z4il" ];
  };
})
