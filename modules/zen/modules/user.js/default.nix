{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    listToAttrs
    mapAttrs
    substring
    ;

  cfg = config.icedos;
  firefoxVersion = substring 0 5 pkgs.firefox.version;
  zen = cfg.applications.zen;

  baseSettings = {
    "browser.download.always_ask_before_handling_new_types" = false;
    "browser.newtabpage.enabled" = false;
    "browser.search.separatePrivateDefault" = false;
    "browser.shell.checkDefaultBrowser" = false;
    "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
    "browser.toolbars.bookmarks.visibility" = "always";
    "dom.webgpu.enabled" = true;
    "general.autoScroll" = true;

    "general.useragent.override" =
      "Mozilla/5.0 (X11; Linux x86_64; rv:${firefoxVersion}) Gecko/${firefoxVersion} Firefox/${firefoxVersion}";

    "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;
    "middlemouse.paste" = false;
    "mousewheel.default.delta_multiplier_x" = 250;
    "mousewheel.with_shift.delta_multiplier_y" = 250;
    "toolkit.scrollbox.verticalScrollDistance" = 2;
    "zen.splitView.change-on-hover" = true;
    "zen.theme.color-prefs.amoled" = true;
    "zen.theme.color-prefs.use-workspace-colors" = false;
    "zen.urlbar.behavior" = "float";
    "zen.view.compact" = true;
    "zen.view.compact.hide-tabbar" = true;
    "zen.view.compact.hide-toolbar" = true;
    "zen.view.show-newtab-button-border-top" = false;
    "zen.view.sidebar-expanded.on-hover" = false;
    "zen.view.use-single-toolbar" = false;
    "zen.welcome-screen.seen" = true;
  };

  nonPrivacySettings = {
    "privacy.clearOnShutdown.downloads" = false;
    "privacy.clearOnShutdown.history" = false;
  };

  privacySettings = {
    "browser.startup.page" = 1;
    "browser.urlbar.suggest.history" = false;
    "browser.urlbar.suggest.recentsearches" = false;
    "pref.privacy.disable_button.cookie_exceptions" = false;
    "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = false;
    "privacy.history.custom" = true;
    "privacy.sanitize.sanitizeOnShutdown" = true;
    "signon.management.page.breach-alerts.enabled" = false;
    "signon.rememberSignons" = false;
  };

  pwaSettings = {
    "browser.toolbars.bookmarks.visibility" = "never";
    "zen.tab-unloader.enabled" = false;
    "zen.view.sidebar-expanded" = false;
    "zen.view.compact.hide-tabbar" = false;
  };

  profileSettings =
    profile:
    baseSettings
    // (if profile.privacy then privacySettings else nonPrivacySettings)
    // (if profile.pwa then pwaSettings else { });
in
{
  home-manager.users = mapAttrs (_: _: {
    programs.zen-browser.profiles = listToAttrs (
      map (profile: {
        name = profile.exec;
        value.settings = profileSettings profile;
      }) zen.profiles
    );
  }) cfg.users;
}
