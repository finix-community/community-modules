{
  note = "generates dinit unit files; finit is pid 1 on a finix host, so nothing here supervises them";

  # no enable switch - defining a service is what makes the module generate
  # anything.
  machine = {
    dinit.services.compat-probe = {
      type = "scripted";
      command = "/bin/sh -c 'echo compat-probe'";
    };
  };
}
