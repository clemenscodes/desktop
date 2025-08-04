{
  self,
  inputs,
  lib,
  config,
  system,
  ...
}: let
  pkgs = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [
          "mongodb"
          "mongodb-compass"
          "lens-desktop"
        ];
    };
  };
  pam = pkgs.writeShellScriptBin "pam" ''
    ${lib.getExe pkgs.kitty} -1 --detach -d "$HOME/.local/src/pam"
  '';
  teams = pkgs.writeShellScriptBin "teams" ''
    while ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; do
      sleep 1
    done
    sleep 3
    ${lib.getExe pkgs.teams-for-linux} --awayOnSystemIdle
  '';
  thunderbird = pkgs.writeShellScriptBin "thunderbird" ''
    while ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; do
      sleep 1
    done
    sleep 3
    ${lib.getExe pkgs.thunderbird}
  '';
  compass = let
    userSecrets = config.home-manager.users.${config.modules.users.name}.sops.secrets;
  in
    pkgs.writeShellScriptBin "compass" ''
      max_retries=30
      retry_delay=1
      count=0

      echo -n "$(${pkgs.bat}/bin/bat ${userSecrets.login_password.path} --style=plain)" | \
        gnome-keyring-daemon \
          --daemonize \
          --replace \
          --unlock \
          --components=secrets

      ${lib.getExe pkgs.mongodb-compass} \
        --importConnections=${userSecrets.compass_connections.path} \
        --passphrase="$(${pkgs.bat}/bin/bat ${userSecrets.compass_password.path} --style=plain)" \
        --ignoreAdditionalCommandLineFlags \
        --password-store="gnome-libsecret"

      while ! ${pkgs.netcat}/bin/nc -z localhost 27017; do
        count=$((count + 1))
        if [ "$count" -ge "$max_retries" ]; then
          echo "Timed out waiting for MongoDB to be available on localhost:27017."
          exit 1
        fi
        sleep "$retry_delay"
      done

      ${lib.getExe pkgs.mongodb-compass} \
        --theme=OS_THEME \
        --no-networkTraffic \
        --no-autoUpdates \
        --no-trackUsageStatistics \
        --no-enableGenAIFeatures \
        --no-enableGenAISampleDocumentPassing \
        --no-enableGenAIFeaturesAtlasProject \
        --no-enableGenAIFeaturesAtlasOrg \
        --no-enableFeedbackPanel \
        --no-enableCreatingNewConnections \
        --no-enableOIDC \
        --no-enableGlobalWrites \
        --enableExplainPlan \
        --enableAggregationBuilderRunPipeline \
        --protectConnectionStrings \
        --enableImportExport \
        --enableShell \
        --enableDevTools \
        --showInsights \
        --readOnly \
        --file=${userSecrets.compass_connections.path} \
        --passphrase="$(${pkgs.bat}/bin/bat ${userSecrets.compass_password.path} --style=plain)" \
        --ignoreAdditionalCommandLineFlags \
        --password-store="gnome-libsecret" \
        $(jq -r '.connections[0].id' ${userSecrets.compass_connections.path}) \
        "$@"
    '';
  dangerous-compass-with-write-access-be-careful-dont-fuck-this-up = let
    userSecrets = config.home-manager.users.${config.modules.users.name}.sops.secrets;
  in
    pkgs.writeShellScriptBin "dangerous-compass-with-write-access-be-careful-dont-fuck-this-up" ''
      ${lib.getExe pkgs.mongodb-compass} \
        --theme=OS_THEME \
        --no-networkTraffic \
        --no-autoUpdates \
        --no-trackUsageStatistics \
        --no-enableGenAIFeatures \
        --no-enableGenAISampleDocumentPassing \
        --no-enableGenAIFeaturesAtlasProject \
        --no-enableGenAIFeaturesAtlasOrg \
        --no-enableFeedbackPanel \
        --no-enableCreatingNewConnections \
        --no-enableOIDC \
        --no-enableGlobalWrites \
        --enableExplainPlan \
        --enableAggregationBuilderRunPipeline \
        --protectConnectionStrings \
        --enableImportExport \
        --enableShell \
        --enableDevTools \
        --showInsights \
        --file=${userSecrets.compass_connections.path} \
        --passphrase="$(${pkgs.bat}/bin/bat ${userSecrets.compass_password.path} --style=plain)" \
        --ignoreAdditionalCommandLineFlags \
        --password-store="gnome-libsecret" \
        $(jq -r '.connections[0].id' ${userSecrets.compass_connections.path}) \
        "$@"
    '';
  lzd = pkgs.writeShellScriptBin "lzd" ''
    ${lib.getExe pkgs.kitty} -1 ${lib.getExe pkgs.lazydocker}
  '';
  lzg = pkgs.writeShellScriptBin "lzg" ''
    ${lib.getExe pkgs.kitty} -1 -d $HOME/.local/src/pam ${lib.getExe pkgs.lazygit}
  '';
  pam-up = pkgs.writeShellScriptBin "pam-up" ''
    docker compose -f $HOME/.local/src/pam/environment/docker-compose.yml up -d
  '';
  pam-down = pkgs.writeShellScriptBin "pam-down" ''
    docker compose -f $HOME/.local/src/pam/environment/docker-compose.yml down
  '';
  is-port-open = pkgs.writeShellApplication {
    name = "is-port-open";
    runtimeInputs = [pkgs.lsof];
    text = ''
      PORT="$1"
      if lsof -i :"$PORT" > /dev/null 2>&1; then
        exit 1
      else
        exit 0
      fi
    '';
  };
  mongo-start-port-forwards = pkgs.writeShellApplication {
    name = "mongo-start-port-forwards";
    runtimeInputs = [
      pkgs.kubectl
      pkgs.jq
      pkgs.lsof
      is-port-open
    ];
    text = ''
      BASE_LOCAL_PORT=27018
      REMOTE_PORT=27017

      port_offset=0

      while ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; do
        sleep 1
      done

      kubectl config get-contexts --output=name --no-headers | while read -r context; do
        echo "🔍 Checking context: $context"

        svc_info=$(kubectl --context="$context" get svc --all-namespaces -o json 2>/dev/null | \
          jq -r '.items[] | select(.spec.ports[]?.port == 27017) | [.metadata.namespace, .metadata.name] | @tsv' | head -n 1)

        if [[ -z "$svc_info" ]]; then
          echo "⚠️ No MongoDB service found in $context — skipping."
          continue
        fi

        namespace=$(echo "$svc_info" | cut -f1)
        service=$(echo "$svc_info" | cut -f2)

        local_port=$((BASE_LOCAL_PORT + port_offset))

        if ! is-port-open "$local_port"; then
          echo "⚠️ Port $local_port already in use — skipping forward for $context"
          continue
        fi

        echo "✅ Forwarding $context:$namespace/$service:$REMOTE_PORT → localhost:$local_port"
        kubectl --context="$context" port-forward svc/"$service" "$local_port:$REMOTE_PORT" -n "$namespace" &

        port_offset=$((port_offset + 1))
      done

      wait
    '';
  };
  mongo-stop-port-forwards = pkgs.writeShellApplication {
    name = "mongo-stop-port-forwards";
    text = ''
      pids="$(pgrep -f 'kubectl.*port-forward.*mongodb-svc')"
      if [ -n "$pids" ]; then
        echo "$pids" | xargs kill
      fi
    '';
  };
in {
  specialisation = {
    nexobility = {
      inheritParentConfig = true;
      configuration = {
        networking = {
          nameservers = [
            "1.1.1.1"
            "8.8.4.4"
          ];
          dhcpcd = {
            extraConfig = ''
              nohook resolv.conf
            '';
          };
          networkmanager = {
            dns = "none";
          };
        };
        security = {
          pki = {
            certificateFiles = ["${self}/certs/local.betterpark.de"];
          };
        };
        home-manager = {
          users = {
            ${config.modules.users.user} = {
              home = {
                file = {
                  ".azure/azuredevops/config" = {
                    text = ''
                      [defaults]
                      organization = https://dev.azure.com/nexobility
                      project = Parking Area Management
                    '';
                  };
                  ".config/activitywatch/aw-rules.json" = {
                    source = "${self}/assets/aw-rules.json";
                  };
                  ".config/activitywatch/aw-qt/aw-qt.toml" = {
                    text = ''
                      [aw-qt]
                      autostart_modules = ["aw-server"]

                      [aw-qt-testing]
                      autostart_modules = ["aw-server"]
                    '';
                  };
                };
                persistence = {
                  "${config.modules.boot.impermanence.persistPath}/home/${config.modules.users.name}" = {
                    directories = [
                      ".azure"
                      ".azure-devops"
                      ".mongodb"
                      ".config/MongoDB Compass"
                      ".config/Lens"
                      ".local/share/activitywatch"
                      ".local/share/nvim"
                      ".local/state/nvim"
                    ];
                  };
                };
                packages =
                  (with pkgs; [
                    teleport
                    kompose
                    kubectl
                    kubefwd
                    kubernetes
                    kubernetes-helm
                    lens
                    mongodb
                    mongosh
                    mongodb-tools
                    mongodb-compass
                    (azure-cli.withExtensions (with azure-cli-extensions; [
                      azure-devops
                    ]))
                    awatcher
                    aw-server-rust
                    xh
                    lsof
                  ])
                  ++ [
                    pam
                    pam-up
                    pam-down
                    teams
                    compass
                    lzg
                    lzd
                    mongo-start-port-forwards
                    mongo-stop-port-forwards
                    is-port-open
                    dangerous-compass-with-write-access-be-careful-dont-fuck-this-up
                  ];
              };
              wayland = {
                windowManager = {
                  hyprland = {
                    settings = {
                      bind = [
                        "$mod SHIFT, P, exec, ${lib.getExe pam}"
                        "$mod , T, exec, ${lib.getExe teams}"
                        "$mod , C, exec, ${lib.getExe compass}"
                        "$mod , I, exec, ${lib.getExe lzd}"
                        "$mod , G, exec, ${lib.getExe lzg}"
                      ];
                    };
                    extraConfig = ''
                      monitor = eDP-1, 1920x1080@60, 0x0, 1
                      monitor = HDMI-A-1, preferred, auto, 1, mirror, eDP-1
                      exec-once = ${lib.getExe teams}
                      exec-once = ${lib.getExe compass}
                      exec-once = ${lib.getExe thunderbird}
                      exec-once = ${lib.getExe pam-up}
                      exec-once = ${lib.getExe mongo-start-port-forwards}
                      exec-once = ${lib.getExe pkgs.awatcher}
                      windowrule = workspace 1, class:(teams-for-linux)
                      windowrule = noinitialfocus, class:(teams-for-linux)
                      windowrule = workspace 2, class:(MongoDB Compass)
                      windowrule = noinitialfocus, class:(MongoDB Compass)
                      windowrule = workspace 3, class:(thunderbird)
                      windowrule = noinitialfocus, class:(thunderbird)
                      windowrule = workspace 4, class:(lazydocker)
                      windowrule = noinitialfocus, class:(lazydocker)
                      windowrule = workspace 5, class:(pam)
                      windowrule = noinitialfocus, class:(pam)
                      windowrule = opacity 0.90,class:(pam|lazydocker|brave-browser|thunderbird|teams-for-linux|MongoDB Compass|codium)
                    '';
                  };
                };
              };
              programs = {
                lazydocker = {
                  enable = true;
                  settings = {
                    gui = {
                      returnImmediately = true;
                      theme = {
                        activeBorderColor = ["red" "bold"];
                        inactiveBorderColor = ["blue"];
                      };
                    };
                    commandTemplates = {
                      dockerCompose = "docker compose";
                    };
                  };
                };
                k9s = {
                  enable = true;
                };
                ssh = {
                  enable = true;
                  matchBlocks = {
                    "ssh.dev.azure.com" = {
                      hostname = "ssh.dev.azure.com";
                      user = "git";
                      identityFile = "${config.home-manager.users.${config.modules.users.name}.sops.secrets."nexobility/ssh_private".path}";
                      identitiesOnly = true;
                    };
                  };
                };
              };
              services = {
                activitywatch = {
                  enable = true;
                  package = pkgs.aw-server-rust;
                };
              };
              modules = {
                development = {
                  git = {
                    enable = true;
                    userName = "Clemens Horn";
                    userEmail = lib.mkForce "clemens.horn@nexobility.de";
                    lazygit = {
                      enable = true;
                    };
                  };
                  postman = {
                    enable = true;
                  };
                  tongo = {
                    enable = true;
                  };
                };
                organization = {
                  libreoffice = {
                    enable = true;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
