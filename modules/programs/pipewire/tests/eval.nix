{
  note = "needs a sound device and a logged-in seat to reach a running graph";

  # this module is an alternative to the pipewire module finix ships, so that
  # one is taken out of the host - two declarations of `programs.pipewire`
  # would just be an eval error. wireplumber is not a separate module here, it
  # hangs off `programs.pipewire.wireplumber`.
  replacesFinixModules = [ "programs/pipewire" ];

  machine = {
    programs.pipewire.enable = true;
    programs.pipewire.wireplumber.enable = true;
  };
}
