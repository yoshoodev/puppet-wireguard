# puppet-wireguard

[![Build Status](https://github.com/voxpupuli/puppet-wireguard/workflows/CI/badge.svg)](https://github.com/voxpupuli/puppet-wireguard/actions?query=workflow%3ACI)
[![Release](https://github.com/voxpupuli/puppet-wireguard/actions/workflows/release.yml/badge.svg)](https://github.com/voxpupuli/puppet-wireguard/actions/workflows/release.yml)
[![Puppet Forge](https://img.shields.io/puppetforge/v/puppet/wireguard.svg)](https://forge.puppetlabs.com/puppet/wireguard)
[![Puppet Forge - downloads](https://img.shields.io/puppetforge/dt/puppet/wireguard.svg)](https://forge.puppetlabs.com/puppet/wireguard)
[![Puppet Forge - endorsement](https://img.shields.io/puppetforge/e/puppet/wireguard.svg)](https://forge.puppetlabs.com/puppet/wireguard)
[![Puppet Forge - scores](https://img.shields.io/puppetforge/f/puppet/wireguard.svg)](https://forge.puppetlabs.com/puppet/wireguard)
[![puppetmodule.info docs](http://www.puppetmodule.info/images/badge.png)](http://www.puppetmodule.info/m/puppet-wireguard)
[![AGPL v3 License](https://img.shields.io/github/license/voxpupuli/puppet-wireguard.svg)](LICENSE)

Puppet module to configure wireguard through systemd-networkd configs

* [Setup](#setup)
* [Example configurations](#example-configurations)
* [Parameter reference](#parameter-reference)
* [Tests](#tests)
* [Contributions](#contributions)
* [License and Author](#-icense-and-author)

## Setup

The module can create firewall rules with [voxpupuli/nftables](https://github.com/voxpupuli/puppet-nftables?tab=readme-ov-file#nftables-puppet-module).
This is enabled by default but can be disabled by setting the `manage_firewall`
parameter to false in the `wireguard::interface` defined resource. You need to
have the `nftables` class in your catalog to use the feature (Version 3.6.0 or
newer).

**Version 3 and older of the module use voxpupuli/ferm to manage firewall rules**

This module can use [systemd-networkd](https://www.freedesktop.org/software/systemd/man/systemd-networkd.html) or [wg-quick](https://manpages.debian.org/wg-quick) to
configure tunnels. For the former, you need to have a systemd-networkd
service resource in your catalog. We recommend [voxpupuli/systemd](https://github.com/voxpupuli/puppet-systemd#systemd)
with `manage_networkd` set to true. You do not need to configure your
entire network with `systemd-networkd`, only the tunnels. That said,
`wg-quick` might be better a better match if you do not want to touch
`systemd`.

Furthermore, this module assumes that you've a dualstack machine. Your IPv4 and
IPv6 addresses will be automatically set to the `destination_addresses` array
from the `wireguard::interface` defined resource. If you don't have dualstack
you need to overwrite the parameter.

There is a structured fact called `wireguard_pubkeys` which is a hash with each
filename without the `.pub` and the content (the public key):

```
# facter -p wireguard_pubkeys
{
  as1234 => "40mH10BbolserhidsruhieudrstlJBB7fxvoPlU=",
  as5678 => "Tci/bHoPColserjfoisehrjioesurrhGpEN+NDueNjUvBA=",
  asblub => "M7lTopd2koserhioesrhiouwerhpcvqSWEviI=",
  notebook => "sK9Ld+p1eH4id+BAuM6lserheoishriouwKhgwFf/HRw=",
  lan => "dIXj6QcWGBWTzq0pwoerjow4eroiwe4jr4CGkXUID3J8rO2k="
}
```
## Example configurations

configure a tunnel with the name as9876.
* listen for incoming traffic on port 9876
* create a ferm rule to allow traffic on the global IPv4/IPv6 addresses
* configure the provided public key from the peer
* assign a IPv4 and IPv6 prefix on the tunnel interface

```puppet
wireguard::interface {'as9876':
  source_addresses => ['2003:4e0:c17:5d::1', '195.37.53.176'],
  public_key       => 'BcxLll1BVxGkehriuehrFvjvX+EBhS4vcDn0R0=',
  endpoint         => 'wireguard.example.com:53668',
  addresses        => [{'Address' => '192.168.123.6/30',},{'Address' => 'fe80::beef:1/64'},],
}
```

configure a tunnel with the name as1234
* listen on port 9876
* don't create firewall rules
* assign a IPv4 and IPv6 prefix on the tunnel interface
  * use /32 for the IPv4 address and add a peer route

```puppet
wireguard::interface {'as1234':
  manage_firewall => false,
  public_key      => 'B1xSG/XTJRLd+GrWDsB06BqnIq8Xud93YVh/LYYYtUY=',
  endpoint        => 'wireguard.example.com:53668',
  addresses       => [{'Address' => '192.168.218.87/32', 'Peer' => '172.20.53.97/32'}, {'Address' => 'fe80::ade1/64',},],
}
````

More examples are available in the [REFERENCE.md](./REFERENCE.md) file.

### Generating preshared keys

Use `wireguard::generate_psk` to generate a cryptographically random, base64-encoded
32-byte PSK for a pair of endpoints. Pass the same two stable identifiers on both
nodes; their order does not matter. Include the interface name to keep separate
tunnels between the same nodes independent.

```puppet
$psk = wireguard::generate_psk('node-a.example.com/wg0', 'node-b.example.com/wg0')

wireguard::interface { 'wg0':
  dport           => 51820,
  manage_firewall => false,
  public_key      => $remote_public_key,
  preshared_key   => $psk,
  endpoint        => $remote_endpoint,
  addresses       => [{'Address' => '192.0.2.1/24'}],
}
```

On the other node, use its local address and the opposite endpoint's public key
and endpoint. The returned string can also be used as `preshared_key` in a `peers`
entry or a `wireguard::peer` resource, with either provider where applicable.
Existing explicitly supplied PSKs remain supported.

Keys are generated during catalog compilation, not on agents, and are reused
from `$vardir/wireguard_psks` on the compiler. An optional third argument selects
a different absolute storage directory. The dedicated directory must be writable
by the Puppet Server user; it is restricted to mode `0700`, with key files at
`0600`. Do not point it at an existing general-purpose directory, since its mode
will be changed. Compilation fails for an invalid stored key rather than silently
replacing it.

Back up this directory securely: deleting a key generates a new PSK on the next
compilation and requires updating both endpoints. All compilers serving these
nodes must use the same persistent storage with working file locking, or catalogs
must be compiled by the same server. Separate `puppet apply` runs on different
nodes do not share storage automatically. Do not publish PSKs as facts or exported
resources. Like explicitly supplied PSKs, generated keys are present in compiled
catalogs and rendered configuration files, so protect access to those as well.

## Parameter reference

All parameters are documented with puppet-strings. You can view the
markdown-rendered result at [REFERENCE.md](./REFERENCE.md).

## Tests

This module has several unit tests and linters configured. You can execute them
by running:

```sh
bundle exec rake test
```

Detailed instructions are in the [CONTRIBUTING.md](.github/CONTRIBUTING.md)
file.

## Contributions

Contribution is fairly easy:

* Fork the module into your namespace
* Create a new branch
* Commit your bugfix or enhancement
* Write a test for it (maybe start with the test first)
* Create a pull request

Detailed instructions are in the [CONTRIBUTING.md](.github/CONTRIBUTING.md)
file.

## License and Author

This module was originally written by [Tim Meusel](https://github.com/bastelfreak).
It's licensed with [AGPL version 3](LICENSE).

