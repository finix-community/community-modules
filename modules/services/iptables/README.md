# iptables

Service module for [iptables](https://www.netfilter.org/projects/iptables/), the classic Linux packet filtering framework.

Loads IPv4 and IPv6 rulesets at boot via a finit task and tears them down cleanly on stop. Also supplies a `providers.firewall` implementation, making it a drop-in alternative to the nftables backend for systems that require iptables.

## Basic usage

```nix
{
  services.iptables = {
    enable = true;
    rulesetV4 = ''
      *filter
      :INPUT DROP [0:0]
      :FORWARD DROP [0:0]
      :OUTPUT ACCEPT [0:0]
      -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      -A INPUT -p tcp --dport 22 -j ACCEPT
      COMMIT
    '';
  };
}
```

## Using the firewall provider

When `services.iptables.enable` is true, this module registers itself as the `providers.firewall` backend (at a lower priority than nftables, so nftables wins if both are enabled). You can use the standard firewall provider options to open ports declaratively:

```nix
{
  services.iptables.enable = true;
  providers.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
    allowedUDPPorts = [ 53 ];
  };
}
```
