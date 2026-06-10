# `steam`

Community module for `steam`. Currently sets up the following: 

- video drivers
- `steam` package
- steam-run (libraries required for steam to run on a non-standard LFH system)

Also allows for extra configuration like environment variables, package overrides, etc. 

Hardware support is not enabled by default, since `finix` does not have a 'standard' device manager. However, this should hopefully change soon with the soon-to-be implemented `providers` abstraction that should hopefully streamline the management of device manager rules. Except for `mdevd`.
