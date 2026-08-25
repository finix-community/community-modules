{
  note = "pulls the 32-bit graphics stack and wants a gpu; far too large to boot in ci";

  machine = {
    programs.steam.enable = true;
    programs.steam.hardware.enable = true;
    programs.steam.protontricks.enable = true;
  };
}
