{ pkgs, ... }:
{
    home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.msaxena = {
            home.packages = with pkgs; [
                openssh
                git
                sqlitebrowser
            ];
            home.stateVersion = "25.05";
    };
    };
    
}