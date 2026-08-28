# flakelet-nginx

nginx provider for the [flakelet](https://github.com/Mic92/flakelet) `http/v1`
contract. It renders server blocks from `/run/flakelet/exports/*.json` into an
include directory and reloads nginx. A path unit re-renders whenever exports
change. NixOS-defined virtual hosts keep working next to the rendered ones.

```nix
{
  imports = [ flakelet-nginx.nixosModules.provider ];
  services.flakelet-nginx = {
    enable = true;
    tls = {
      certificate = "/var/lib/acme/@host@/fullchain.pem";
      key = "/var/lib/acme/@host@/key.pem";
    };
  };
}
```

`tls = null` serves plain http. `@host@` expands to the vhost name, which
allows per-site ACME certificates. A fixed path serves one wildcard
certificate for all vhosts. The certificate must already exist on the host
because domains are only known at runtime, too late to request ACME
certificates during evaluation.

If other vhosts bind specific addresses instead of wildcards, set
`services.flakelet-nginx.listenAddresses` to the same list. Otherwise the
rendered vhosts listen on a socket that never receives those connections.

## Options

`services.flakelet-nginx.*`:

| option            | type                          | default                                       | description |
| ----------------- | ----------------------------- | --------------------------------------------- | ----------- |
| `enable`          | bool                          | `false`                                       | enable the provider |
| `tls`             | null or `{ certificate, key }`| `null`                                        | serve vhosts over TLS with an http→https redirect; `null` = plain http |
| `tls.certificate` | str                           | —                                             | fullchain path, `@host@` expands to the vhost name |
| `tls.key`         | str                           | —                                             | private key path, `@host@` expands to the vhost name |
| `listenAddresses` | list of str                   | `config.services.nginx.defaultListenAddresses`| addresses the rendered vhosts listen on; must match what the other vhosts bind |
| `exportsDir`      | path                          | `/run/flakelet/exports`                       | where flakelet publishes exports |

Schema: [contracts/http-v1.json](https://github.com/Mic92/flakelet/blob/main/contracts/http-v1.json).
The provider announces `{ "contract": "http/v1" }` in `/etc/flakelet/providers.d/`.
