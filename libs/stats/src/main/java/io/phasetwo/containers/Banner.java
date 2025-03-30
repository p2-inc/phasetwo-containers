package io.phasetwo.containers;

public final class Banner {

  private static String BANNER;

  private static final String BLUE = "\u001B[34m";
  private static final String RESET = "\u001B[0m";
  private static final boolean isWindows = System.getProperty("os.name").toLowerCase().contains("win");

  private static StringBuilder append(StringBuilder o, String line, String color) {
    if (!isWindows) {
      o.append(color).append(line).append(RESET).append("\n");
    } else {
      o.append(line).append("\n");
    }
    return o;
  }
    
  static {
    String abled =
        Stats.statsEnabled()
            ? "Anonymous usage statistics collection is enabled.            "
            : "Anonymous usage statistics collection is disabled.           ";
    StringBuilder o = new StringBuilder();
    append(o, "██████╗ ██╗  ██╗ █████╗ ███████╗███████╗    ██╗ ██╗", BLUE);
    append(o, "██╔══██╗██║  ██║██╔══██╗██╔════╝██╔════╝   ██╔╝██╔╝", BLUE);
    append(o, "██████╔╝███████║███████║███████╗█████╗    ██╔╝██╔╝ ", BLUE);
    append(o, "██╔═══╝ ██╔══██║██╔══██║╚════██║██╔══╝   ██╔╝██╔╝  ", BLUE);
    append(o, "██║     ██║  ██║██║  ██║███████║███████╗██╔╝██╔╝   ", BLUE);
    append(o, "╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═╝    ", BLUE);
    o.append("                                                             ").append("\n");
    o.append("   https://phasetwo.io                                       ").append("\n");
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
