package io.phasetwo.containers;

import com.google.auto.service.AutoService;
import com.google.common.collect.Maps;
import io.phasetwo.service.model.OrganizationProvider;
import jakarta.ws.rs.core.MultivaluedHashMap;
import jakarta.ws.rs.core.MultivaluedMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import org.keycloak.Config.Scope;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.utils.KeycloakModelUtils;
import org.keycloak.provider.ServerInfoAwareProviderFactory;

@AutoService(VersionProviderFactory.class)
public class PhaseTwoVersionProvider
    implements VersionProvider, VersionProviderFactory, ServerInfoAwareProviderFactory {

  public static final String PROVIDER_ID = "phasetwo-version";

  @Override
  public String getId() {
    return PROVIDER_ID;
  }

  @Override
  public VersionProvider create(KeycloakSession session) {
    return this;
  }

  @Override
  public String printBanner() {
    return Banner.getBanner();
  }

  @Override
  public Map<String, String> getVersion() {
    Map<String, String> v = Maps.newHashMap();
    v.put("version", org.keycloak.common.Version.VERSION);
    v.put("vendor", Version.getVendor());
    v.put("commit", Version.getCommit());
    v.put("timestamp", Version.getTimestamp());
    return v;
  }

  @Override
  public Map<String, String> getOperationalInfo() {
    return getVersion();
  }

  @Override
  public void init(Scope config) {
    System.err.println(printBanner());
  }

  @Override
  public void postInit(KeycloakSessionFactory factory) {
    try {
      final MultivaluedMap<String, Object> info =
          new MultivaluedHashMap<String, Object>(getVersion());
      KeycloakModelUtils.runJobInTransaction(
          factory,
          s -> {
            OrganizationProvider o = s.getProvider(OrganizationProvider.class);
            AtomicLong clients = new AtomicLong(0l);
            AtomicLong idps = new AtomicLong(0l);
            AtomicLong orgs = new AtomicLong(0l);
            AtomicLong realms = new AtomicLong(0l);
            AtomicLong users = new AtomicLong(0l);
            try {
              s.realms()
                  .getRealmsStream()
                  .forEach(
                      r -> {
                        realms.getAndIncrement();
                        s.getContext().setRealm(r);
                        clients.getAndAdd(s.clients().getClientsCount(r));
                        idps.getAndAdd(s.identityProviders().count());
                        orgs.getAndAdd(o.getOrganizationsCount(r, null));
                        users.getAndAdd(s.users().getUsersCount(r));
                      });
              info.add("num_clients", clients.get());
              info.add("num_idps", idps.get());
              info.add("num_orgs", orgs.get());
              info.add("num_realms", realms.get());
              info.add("num_users", users.get());
            } catch (Exception e) {
              e.printStackTrace();
            }
          });

      //      Stats.collect(Version.getVendor(), org.keycloak.common.Version.VERSION,
      // Version.getCommit());
      Stats.collect(info);
    } catch (Exception e) {
    }
  }

  @Override
  public void close() {}
}
