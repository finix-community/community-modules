{
  note = "drives rgb controllers over i2c/smbus, none of which a vm has";

  machine = {
    services.hardware.openrgb.enable = true;
  };
}
