# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mapAttrsToList
    concatStringsSep
    optionalAttrs
    ;
  inherit (lib.types)
    attrsOf
    enum
    path
    submodule
    nullOr
    listOf
    str
    ;
  inherit (import ./option-types.nix { inherit lib; }) lockFlagEnum bookmarkType proxyConfig;

  cfg = config.securix.chromium;

  # `extraOpts` is a plain attribute set: a nested `mkIf` is not discharged and
  # would land verbatim in the policy JSON.
  proxySettings = optionalAttrs (cfg.proxy != null) {
    ProxySettings = {
      ProxyMode =
        if cfg.proxy.httpProxy != null then
          "fixed_servers"
        else if cfg.proxy.autoConfigURL != null then
          "pac_script"
        else
          "auto_detect";
      ProxyBypassList = concatStringsSep "," cfg.proxy.noProxy;
    }
    // optionalAttrs (cfg.proxy.autoConfigURL != null) {
      ProxyPacUrl = cfg.proxy.autoConfigURL;
      # Do not fall back to a direct connection when the PAC script cannot be
      # fetched.
      # TODO: expose an option called `cfg.proxy.autoConfigFailSafe`
      ProxyPacMandatory = true;
    }
    // optionalAttrs (cfg.proxy.httpProxy != null) { ProxyServer = cfg.proxy.httpProxy; };
  };
in
{
  options.securix.chromium = {
    enable = mkEnableOption "Chromium pre-configuration";
    enableEncryptedMediaExtensions = mkEnableOption ''
      allow encrypted media extensions to be used.

      This is required for websites like Netflix or YouTube.
    '';

    lockFlags = mkOption {
      type = listOf (enum lockFlagEnum);

      default = [
        "allow-default-overrides"
        "allow-user-messaging-overrides"
      ];

      description = ''
        The lock flags determine how locked down the Chromium configuration is.

        By default, we do not let the user install any extension, but we still
        let them modify the Chromium defaults.
      '';
    };

    proxy = mkOption {
      type = nullOr (submodule proxyConfig);
      default = null;
      description = ''
        Proxy configuration for this instance of Chromium.
        By default, it configures nothing.
      '';
    };

    homepage = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        URL of the home page, or `null` to leave the browser default alone.
      '';
    };

    securityDevices = mkOption {
      type = attrsOf path;
      default = { };
      description = ''
        PKCS#11 modules to register, keyed by the name Chromium displays for
        the security device.
      '';
    };

    extensions = mkOption {
      type = listOf str;
      default = [ ];
      example = [
        "gcbommkclmclpchllfjekcdonpmejbdp" # https everywhere
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
      ];
      description = ''
        List of extension IDs to install from the Chrome store.
      '';
    };

    bookmarks = mkOption {
      type = attrsOf (attrsOf (submodule bookmarkType));
      default = { };
      example = ''
        {
          Productivity = {
            Github = {
              href = "https://github.com";
              icon = "github.png";
            };
          };

          Entertainment = {
            Youtube = {
              href = "https://youtube.com";
              icon = "si-youtube";
            };
          };
        }
      '';
      description = ''
        Bookmarks to show to homepage and firefox bookmarks.
      '';
    };
  };

  config = mkIf cfg.enable {
    # programs.chromium only writes policy files, it installs nothing.
    environment.systemPackages = [ pkgs.chromium ];

    # Chromium has no policy for PKCS#11 modules: it reads the user NSS
    # database in ~/.pki/nssdb, and nixpkgs' NSS does not load p11-kit modules.
    systemd.user.services.securix-register-security-devices = mkIf (cfg.securityDevices != { }) {
      description = "Register PKCS#11 security devices in the user NSS database";
      wantedBy = [ "default.target" ];
      path = [ pkgs.nssTools ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        db="$HOME/.pki/nssdb"
        if [ ! -f "$db/pkcs11.txt" ]; then
          mkdir -p "$db"
          certutil -N --empty-password -d "sql:$db"
        fi

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: library: ''
            # Delete first so the entry follows the store path across upgrades.
            modutil -dbdir "sql:$db" -force -delete ${lib.escapeShellArg name} || true
            modutil -dbdir "sql:$db" -force -add ${lib.escapeShellArg name} \
              -libfile ${lib.escapeShellArg library}
          '') cfg.securityDevices
        )}
      '';
    };

    programs.chromium = {
      enable = true;

      homepageLocation = cfg.homepage;

      extraOpts = {
        # Always show the bookmark bar.
        BookmarkBarEnabled = true;
        # Always let the user create more profiles.
        BrowserAddPersonEnabled = true;
        # Always let the user use the guest mode if they want.
        BrowserGuestModeEnabled = true;
        # Let the user edit bookmarks if needed.
        EditBookmarksEnabled = true;

        # TODO: allow customization of the label.
        EnterpriseCustomLabel = "Securix";
        EnterpriseCustomLabelForBrowser = "Securix";
        # EnterpriseLogoUrl = "";
        # EnterpriseLogoUrlForBrowser = "";
        # TODO: should we enable this security?
        # EnterpriseRealTimeUrlCheckMode = false;

        # Try to upgrade connections to HTTPS as much as possible.
        HttpsUpgradesEnabled = true;

        # Here are a bunch of power savings knobs.
        # We try to optimize for a moderate power saving experience
        # by default.
        HighEfficiencyModeEnabled = true;
        IntensiveWakeUpThrottlingEnabled = true;
        MemorySaverModeSavings = 1; # 0 or 2
        BatterySaverModeAvailability = true;

        # Allow DNS interception to determine whether
        # we have a proxy that knows how to deal with certain DNS.
        # Allow to suggest "Try http://intranet" error messages.
        IntranetRedirectBehavior = 3;

        # Home page != New tab page.
        HomepageIsNewTabPage = false;
        # Always restore previous tabs on startup.
        RestoreOnStartup = 1;
        # Show the home button.
        ShowHomeButton = true;

        # In general, Autoplay is never a fun feature.
        AutoplayAllowed = false;

        # Some websites may require it.
        BlockThirdPartyCookies = true;

        # Isolate all origins into their own process/sandbox.
        # IsolateOrigins takes a list of origins, SitePerProcess is the
        # blanket switch.
        SitePerProcess = true;
        # Block any external extension to install.
        BlockExternalExtensions = true;
        # By default, we will block any extension install, mirroring what the
        # Firefox side does. Unlocking it is opt-in through the lock flags.
        ExtensionInstallBlocklist = lib.optionals (!lib.elem "allow-extension-installs" cfg.lockFlags) [
          "*"
        ];
        # Block developer mode for extensions.
        ExtensionDeveloperModeSettings = 1;

        # Allow system CA certificates.
        CAPlatformIntegrationEnabled = true;
        # Let the user only provision *user* certificates.
        CACertificateManagementAllowed = 1;

        # Do not use Chromium native password manager.
        PasswordManagerEnabled = false;

        # Forbid all generative AI from Google.
        GenAiDefaultSettings = 2; # Do not allow GenAI features.
        BuiltInAIAPIsEnabled = false;

        # Do not let the browser use Google to obtain accurate time information.
        BrowserNetworkTimeQueriesEnabled = false;

        # Disable Google feedback surveys.
        FeedbackSurveysEnabled = false;
        # Disable Google Web Store icon.
        HideWebStoreIcon = true;
        # Disable any telemetry to Google.
        MetricsReportingEnabled = false;
        # Disable any advertising from Google.
        PromotionsEnabled = false;
        # Do not recommend media.
        MediaRecommendationsEnabled = false;
        # Do not report domain reliability to Google.
        DomainReliabilityAllowed = false;
        # Ensure that the Accept-Language and navigator.languages options
        # are privacy-preserving.
        ReduceAcceptLanguageEnabled = true;

        # These options controls nudges to the user
        # to restart Chromium to benefit from updates.
        # Sometimes, critical security updates.
        # Or 1
        RelaunchNotification = 2;
        # Every day.
        RelaunchNotificationPeriod = 86400000;

        # RequireOnlineRevocationChecksForLocalAnchors = true;

        # Do not allow the browser connect to a Google account.
        # Even if the user logs in to any Google service.
        BrowserSignin = 0;

        # Disable the usage of built-in DNS client.
        # Use the system DNS resolver.
        BuiltInDnsClientEnabled = false;

        # TODO: allow DOH by default?
        # More secure than usual DNS.
        # DnsOverHttpsMode = "automatic";
        # DnsOverHttpsTemplates = "";

        # Do not care if Chromium is by default.
        DefaultBrowserSettingEnabled = false;

        # New Tab parameters.
        # Provide some customizations options someday.
        NTPCardsVisible = false;
        NTPCustomBackgroundEnabled = false;
        NTPFooterExtensionAttributionEnabled = true;
        NTPFooterManagementNoticeEnabled = true;

        # Future architecture for the PDF viewer.
        PdfViewerOutOfProcessIframeEnabled = true;

        # Enable PQC options by default.
        PostQuantumKeyAgreementEnabled = true;
        # Enable HTTP/3 QUIC by default.
        QuicAllowed = true;
        # Do not let WebAuthn store credentials on broken TLS certificates.
        AllowWebAuthnWithBrokenTlsCerts = false;

        # Pre-installed bookmarks
        ManagedBookmarks =
          let
            mkItems = mapAttrsToList (
              name: { href, ... }: {
                inherit name;
                url = href;
              }
            );
            mkChildren = folder: values: {
              children = mkItems values;
              name = folder;
            };
          in
          mapAttrsToList mkChildren cfg.bookmarks;
      }
      // proxySettings;

      extensions = if cfg.extensions == [ ] then null else cfg.extensions;
    };
  };
}
