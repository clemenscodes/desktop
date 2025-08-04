{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.modules;
  homeCfg = config.home-manager.users.${user};
  inherit (cfg.users) user;
  inherit (cfg.boot.impermanence) persistPath;
  pShadow = "${persistPath}/etc/shadow";
in {
  system = {
    activationScripts = {
      etc_shadow = ''
        [ -f "/etc/shadow" ] && cp /etc/shadow ${pShadow}
        [ -f "${pShadow}" ] && cp ${pShadow} /etc/shadow
      '';
      users = {
        deps = ["etc_shadow"];
      };
    };
  };
  systemd = {
    services = {
      "etc_shadow_persistence" = {
        enable = true;
        description = "Persist /etc/shadow on shutdown.";
        wantedBy = ["multi-user.target"];
        path = [pkgs.util-linux];
        unitConfig = {
          defaultDependencies = true;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = pkgs.writeShellScript "persist_etc_shadow" ''
            mkdir --parents "${persistPath}/etc"
            cp /etc/shadow ${pShadow}
          '';
        };
      };
    };
  };
  users = {
    mutableUsers = false;
    users = {
      ${user} = {
        hashedPasswordFile = lib.mkIf cfg.security.sops.enable (config.sops.secrets.password.path);
      };
    };
  };
  networking = {
    wireless = {
      secretsFile = config.sops.secrets.wifi.path;
      networks = {
        "ext:home_uuid" = {
          priority = 1;
          pskRaw = "ext:home_psk";
        };
        "ext:alt_home_uuid" = {
          priority = 2;
          pskRaw = "ext:alt_home_psk";
        };
      };
    };
  };
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    secrets = {
      password = {
        neededForUsers = true;
      };
      wifi = {
        neededForUsers = true;
      };
      mullvad = {
        neededForUsers = true;
      };
    };
  };
  modules = {
    users = {
      initialHashedPassword = null;
    };
    security = {
      enable = true;
      sops = {
        enable = true;
      };
    };
    networking = {
      torrent = {
        enable = true;
        mullvadAccountSecretPath = config.sops.secrets.mullvad.path;
        mullvadDns = true;
      };
    };
  };
  home-manager = {
    users = {
      ${user} = {
        accounts = {
          email = {
            accounts = {
              "clemens.horn@nexobility.de" = {
                smtp = {
                  tls = {
                    useStartTls = true;
                  };
                };
              };
            };
          };
        };
        home = {
          sessionVariables = {
            KUBECONFIG = "${homeCfg.sops.secrets.kubeconfig.path}";
          };
          file = {
            ".ssh/id_rsa_nexobility.pub" = {
              source = homeCfg.lib.file.mkOutOfStoreSymlink "${homeCfg.sops.secrets."nexobility/ssh_public".path}";
            };
          };
        };
        modules = {
          security = {
            sops = {
              enable = true;
            };
          };
          storage = {
            enable = true;
            rclone = {
              enable = true;
              gdrive = {
                enable = true;
                clientId = homeCfg.sops.secrets."rclone/gdrive/clientId".path;
                clientSecret = homeCfg.sops.secrets."rclone/gdrive/clientSecret".path;
                token = homeCfg.sops.secrets."rclone/gdrive/token".path;
                encryption_password = homeCfg.sops.secrets."rclone/gdrive/password".path;
                encryption_salt = homeCfg.sops.secrets."rclone/gdrive/salt".path;
              };
            };
          };
          organization = {
            enable = true;
            email = {
              enable = true;
              thunderbird = {
                enable = true;
              };
              accounts = [
                {
                  address = "horn_clemens@t-online.de";
                  primary = false;
                  realName = "Clemens Horn";
                  userName = "horn_clemens@t-online.de";
                  smtpHost = "securesmtp.t-online.de";
                  smtpPort = 465;
                  imapHost = "secureimap.t-online.de";
                  imapPort = 993;
                  secretName = "email/horn_clemens@t-online.de/password";
                }
                {
                  address = "me@clemenshorn.com";
                  primary = false;
                  realName = "Clemens Horn";
                  userName = "me@clemenshorn.com";
                  smtpHost = "box.clemenshorn.com";
                  smtpPort = 465;
                  imapHost = "box.clemenshorn.com";
                  imapPort = 993;
                  secretName = "email/me@clemenshorn.com/password";
                }
                {
                  address = "clemens.horn@mni.thm.de";
                  primary = false;
                  realName = "Clemens Horn";
                  userName = "chrn48";
                  smtpHost = "mailgate.thm.de";
                  smtpPort = 465;
                  imapHost = "mailgate.thm.de";
                  imapPort = 993;
                  secretName = "email/clemens.horn@mni.thm.de/password";
                }
                {
                  address = "clemens.horn@nexobility.de";
                  primary = true;
                  realName = "Clemens Horn";
                  userName = "clemens.horn@nexobility.de";
                  smtpHost = "smtp.office365.com";
                  smtpPort = 587;
                  imapHost = "outlook.office365.com";
                  imapPort = 993;
                  secretName = "email/clemens.horn@nexobility.de/password";
                }
              ];
            };
          };
        };
        programs = {
          zsh = {
            initExtra = let
              gh_token =
                if cfg.security.sops.enable
                then ''
                  if [[ -o interactive ]]; then
                    export GH_TOKEN=$(${pkgs.bat}/bin/bat ${homeCfg.sops.secrets.github_token.path} --style=plain)
                  fi
                ''
                else "";
              hetzner_token =
                if cfg.security.sops.enable
                then ''
                  if [[ -o interactive ]]; then
                    export HCLOUD_TOKEN=$(${pkgs.bat}/bin/bat ${homeCfg.sops.secrets.hetzner_token.path} --style=plain)
                  fi
                ''
                else "";
              cachix_auth_token =
                if cfg.security.sops.enable
                then ''
                  if [[ -o interactive ]]; then
                    export CACHIX_AUTH_TOKEN=$(${pkgs.bat}/bin/bat ${homeCfg.sops.secrets.cachix_auth_token.path} --style=plain)
                  fi
                ''
                else "";
              azure_pat =
                if cfg.security.sops.enable
                then ''
                  if [[ -o interactive ]]; then
                    export AZURE_DEVOPS_EXT_PAT=$(<${homeCfg.sops.secrets.azure_pat.path})
                  fi
                ''
                else "";
              open_api =
                if cfg.security.sops.enable
                then ''
                  if [[ -o interactive ]]; then
                    export OPENAI_API_KEY=$(<${homeCfg.sops.secrets.open_api_key.path})
                  fi
                ''
                else "";
            in
              /*
              bash
              */
              ''
                ${builtins.toString gh_token}
                ${builtins.toString hetzner_token}
                ${builtins.toString cachix_auth_token}
                ${builtins.toString azure_pat}
                ${builtins.toString open_api}
              '';
          };
        };
        nix = {
          extraOptions = ''
            !include ${homeCfg.sops.secrets.nix_access_tokens.path}
          '';
        };
        sops = {
          defaultSopsFile = ./secrets/secrets.yaml;
          secrets = {
            "email/clemens.horn@nexobility.de/password" = {};
            "email/clemens.horn@mni.thm.de/password" = {};
            "email/horn_clemens@t-online.de/password" = {};
            "email/me@clemenshorn.com/password" = {};
            github_token = {};
            cachix_auth_token = {};
            hetzner_token = {};
            nix_access_tokens = {};
            thmvpnuser = {};
            thmvpnpass = {};
            rpcn = {};
            "rclone/gdrive/clientId" = {};
            "rclone/gdrive/clientSecret" = {};
            "rclone/gdrive/token" = {};
            "rclone/gdrive/password" = {};
            "rclone/gdrive/salt" = {};
            compass_password = {};
            login_password = {};
            azure_pat = {};
            compass_connections = {};
            open_api_key = {};
            kubeconfig = {};
            "nexobility/ssh_private" = {};
            "nexobility/ssh_public" = {};
          };
        };
      };
    };
  };
}
