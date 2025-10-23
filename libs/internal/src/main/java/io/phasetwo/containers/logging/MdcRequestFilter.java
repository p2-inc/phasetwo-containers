package io.phasetwo.containers.logging;

import jakarta.annotation.Priority;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.util.Optional;
import lombok.extern.jbosslog.JBossLog;
import org.jboss.logging.MDC;
import org.keycloak.models.KeycloakSession;
import org.keycloak.utils.KeycloakSessionUtil;

@JBossLog
@Provider
@Priority(9999)
public class MdcRequestFilter implements ContainerRequestFilter {

  @Override
  public void filter(ContainerRequestContext requestContext) throws IOException {
    KeycloakSession session = KeycloakSessionUtil.getKeycloakSession();
    log.tracef(
        "Request %s %s has session %s",
        requestContext.getMethod(), requestContext.getUriInfo().getPath(), session);
    if (session != null
        && session.getContext() != null
        && session.getContext().getRealm() != null) {
      String realmName = session.getContext().getRealm().getName();
      MDC.put("realm", realmName);
    }
    getCluster().ifPresent(cluster -> {
        MDC.put("cluster", cluster);
      });
  }

  public static final String PHASETWO_CLUSTER_KEY = "PHASETWO_CLUSTER";
  
  private static Optional<String> getCluster() {
    return Optional.ofNullable(System.getenv(PHASETWO_CLUSTER_KEY));
  }
}
