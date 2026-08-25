{
  note = "polkit agent for a graphical session; a headless vm has no session to authenticate for";

  machine =
    { modules, ... }:
    {
      # the module asserts polkit and elogind are on. elogind is part of the
      # finix base system; polkit is opt-in, so it has to be pulled in the way
      # a real host would.
      imports = [ modules.polkit ];

      services.elogind.enable = true;
      services.polkit.enable = true;
      services.udev.enable = true;

      services.soteria.enable = true;
    };
}
