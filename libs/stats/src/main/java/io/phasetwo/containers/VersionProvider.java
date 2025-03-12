package io.phasetwo.containers;

import java.util.Map;
import org.keycloak.provider.Provider;

public interface VersionProvider extends Provider {

  String printBanner();

  Map<String, String> getVersion();
}
