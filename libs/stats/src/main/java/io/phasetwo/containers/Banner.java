package io.phasetwo.containers;

public final class Banner {

  private static String BANNER;

  static {
    String abled =
        Stats.statsEnabled()
            ? "Anonymous usage statistics collection is enabled.            "
            : "Anonymous usage statistics collection is disabled.           ";
    StringBuilder o = new StringBuilder();
    o.append("         dP                                       d8'    d8' ").append("\n");
    o.append("         88                                      d8'    d8'  ").append("\n");
    o.append("88d888b. 88d888b. .d8888b. .d8888b. .d8888b.    d8'    d8'   ").append("\n");
    o.append("88'  `88 88'  `88 88'  `88 Y8ooooo. 88ooood8   d8'    d8'    ").append("\n");
    o.append("88.  .88 88    88 88.  .88       88 88.  ...  d8'    d8'     ").append("\n");
    o.append("88Y888P' dP    dP `88888P8 `88888P' `88888P' 88     88       ").append("\n");
    o.append("88                                                           ").append("\n");
    o.append("dP                                        https://phasetwo.io").append("\n");
    o.append("                                                             ").append("\n");
    o.append("You are using the **Phase Two** build of Keycloak from       ").append("\n");
    o.append("   https://quay.io/repository/phasetwo/phasetwo-keycloak     ").append("\n");
    o.append("Information on how this build differs from the main is       ").append("\n");
    o.append("   availble at https://github.com/p2-inc/phasetwo-containers ").append("\n");
    o.append(abled).append("\n");
    o.append("Please include this information when opening an issue:       ").append("\n");
    o.append("  - Version: ").append(org.keycloak.common.Version.VERSION).append("\n");
    o.append("  - Vendor: ").append(Version.getVendor()).append("\n");
    o.append("  - Commit: ").append(Version.getCommit()).append("\n");
    o.append("  - Timestamp: ").append(Version.getTimestamp()).append("\n");
    BANNER = o.toString();
  }

  public static void printBanner() {
    System.err.println(BANNER);
  }

  public static String getBanner() {
    return BANNER;
  }
}
