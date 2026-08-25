{
  note = "a wayland compositor needs a gpu and a seat; the test vm has neither";

  machine = {
    programs.river.enable = true;

    # the module asserts this is non-empty
    programs.river.init = ''
      riverctl map normal Super Return spawn foot
    '';
  };
}
