{
  config,
  pkgs,
  ...
}: {
  services.netbox = {
    enable = true;
    #settings.ALLOWED_HOSTS = [ "netbox.home.mayursaxena.com" ]
    listenAddress = "*";
  };
}
