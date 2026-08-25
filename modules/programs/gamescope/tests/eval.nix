{
  note = "a compositor needs a gpu and a seat; the test vm has neither";

  machine = {
    programs.gamescope.enable = true;
  };
}
