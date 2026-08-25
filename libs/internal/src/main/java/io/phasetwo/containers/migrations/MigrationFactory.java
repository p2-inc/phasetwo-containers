package io.phasetwo.containers.migrations;

import com.google.auto.service.AutoService;
import lombok.extern.jbosslog.JBossLog;
import org.keycloak.Config.Scope;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.RealmModel;
import org.keycloak.models.utils.KeycloakModelUtils;
import org.keycloak.provider.Provider;
import org.keycloak.provider.ProviderFactory;

@JBossLog
@AutoService(ProviderFactory.class)
public class MigrationFactory implements Provider, ProviderFactory {

  public static final String PROVIDER_ID = "phasetwo-migrations";

  @Override
  public String getId() {
    return PROVIDER_ID;
  }

  @Override
  public Provider create(KeycloakSession session) {
    return this;
  }

  @Override
  public void init(Scope config) {}

  @Override
  public void postInit(KeycloakSessionFactory factory) {
    try {
      KeycloakModelUtils.runJobInTransaction(
          factory,
          s -> {
            try {
              s.realms()
                  .getRealmsStream()
                  .forEach(
                      r -> {
                        updatePhaseTwoAdminTheme(r);
                      });
            } catch (Exception e) {
              log.warn("Error updating admin theme", e);
            }
          });
    } catch (Exception e) {
    }
  }

  @Override
  public void close() {}

  private static final String OLD_ADMIN_THEME = "phasetwo.v2";
  private static final String NEW_ADMIN_THEME = "phasetwo-ui";

  private static void updatePhaseTwoAdminTheme(RealmModel realm) {
    if (OLD_ADMIN_THEME.equals(realm.getAdminTheme())) {
      log.infof("Updating admin theme for %s to %s", realm.getName(), NEW_ADMIN_THEME);
      realm.setAdminTheme(NEW_ADMIN_THEME);
    }
  }
}
