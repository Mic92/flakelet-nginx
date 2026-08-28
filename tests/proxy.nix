# A flakelet publishes exports.http.web, the provider renders a vhost for
# it, nginx proxies to the service. Removing the entry removes the vhost.
{
  flakeletModule,
  providerModule,
  buildArtifact,
}:
{ pkgs, ... }:
let
  # Prebuilt on the host: nspawn test containers have no writable store.
  web = buildArtifact pkgs {
    name = "web";
    module =
      { ... }:
      {
        impl =
          { inputs, ... }:
          let
            inherit (inputs.nixpkgs) pkgs;
            inherit (inputs.flakelet) name contracts;
          in
          {
            services.${name} = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.python3}/bin/python3 -m http.server -d /var/lib/${name} 8000";
                ExecStartPre = "${pkgs.bash}/bin/sh -c 'echo hello > /var/lib/${name}/index.html'";
                DynamicUser = true;
                StateDirectory = name;
              };
            };
            exports.http.web = contracts.http {
              host = "web.example";
              upstream = "127.0.0.1:8000";
              websockets = true;
              extra.nginx = "add_header X-Flakelet yes;";
            };
          };
      };
  };
in
{
  name = "flakelet-nginx-proxy";
  containers.machine = {
    imports = [
      flakeletModule
      providerModule
    ];
    services.flakelet-nginx.enable = true;
    # A host-defined vhost keeps working next to the rendered ones.
    services.nginx.virtualHosts."static.example".locations."/".return = "200 static";
    services.flakelets = {
      enable = true;
      services.web.prebuilt = web;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("web.service", timeout=600)
    machine.wait_until_succeeds("test -e /run/flakelet-nginx/web.conf")
    machine.wait_until_succeeds("curl -sf -H 'Host: web.example' http://127.0.0.1/ | grep -qx hello")
    machine.succeed("curl -sfI -H 'Host: web.example' http://127.0.0.1/ | grep -q 'X-Flakelet: yes'")
    machine.succeed("curl -sf -H 'Host: static.example' http://127.0.0.1/ | grep -qx static")

    machine.succeed("flakelet remove web")
    machine.wait_until_succeeds("test ! -e /run/flakelet-nginx/web.conf")
    machine.wait_until_fails("curl -sf -H 'Host: web.example' http://127.0.0.1/ | grep -qx hello")
    machine.succeed("curl -sf -H 'Host: static.example' http://127.0.0.1/ | grep -qx static")
  '';
}
