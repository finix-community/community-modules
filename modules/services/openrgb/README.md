# OpenRGB

> [!WARNING]  
> If you're using an intel cpu, explicitly set
> ```nix
> {
>   services.openrgb.motherboard = "intel";
> }
> ```
> 
> This will be fixed after finix/#103 is merged.

An openrgb module that stars the necessary openrgb server on boot
and allows setting some common options like port.
