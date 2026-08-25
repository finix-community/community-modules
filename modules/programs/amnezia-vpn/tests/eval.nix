{
  note = "gui client started by hand from a desktop session; there is nothing to assert on a headless vm";

  machine = {
    programs.amnezia-vpn.enable = true;
  };
}
