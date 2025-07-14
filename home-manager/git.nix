{vars, ...}: {
  programs = {
    git = {
      enable = true;
      userEmail = vars.userEmail;
      userName = vars.fullName;
    };
  };
}
