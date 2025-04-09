package io.phasetwo.containers.stats;

import jakarta.ws.rs.core.MultivaluedHashMap;
import jakarta.ws.rs.core.MultivaluedMap;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;

/** Helper for collecting usage stats */
public final class Stats {

  public static final String PHASETWO_ANALYTICS_DISABLED_KEY = "PHASETWO_ANALYTICS_DISABLED";
  public static final String PHASETWO_ANALYTICS_URL = "https://stats.authit.dev/collect";

  public static boolean statsEnabled() {
    String disabled = System.getenv(PHASETWO_ANALYTICS_DISABLED_KEY);
    return !(Boolean.valueOf(disabled));
  }

  public static void collect(String name, String version, String commit, Object... args)
      throws IOException {
    MultivaluedMap<String, Object> info = new MultivaluedHashMap<String, Object>();
    info.add("name", name);
    info.add("version", version);
    info.add("commit", commit);
    if (args != null) info.addAll("args", args);
    collect(info);
  }

  public static void collect(MultivaluedMap<String, Object> params) throws IOException {
    if (!statsEnabled()) {
      return; // do nothing if anaylitics is disabled
    }

    StringBuilder urlWithParams = new StringBuilder(PHASETWO_ANALYTICS_URL);
    if (!params.isEmpty()) {
      urlWithParams.append("?");
      boolean first = true;
      for (Map.Entry<String, java.util.List<Object>> entry : params.entrySet()) {
        for (Object value : entry.getValue()) {
          if (!first) {
            urlWithParams.append("&");
          }
          urlWithParams
              .append(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8))
              .append("=")
              .append(URLEncoder.encode(value.toString(), StandardCharsets.UTF_8));
          first = false;
        }
      }
    }

    try (CloseableHttpClient httpClient = HttpClients.createDefault()) {
      HttpGet request = new HttpGet(urlWithParams.toString());
      try (CloseableHttpResponse response = httpClient.execute(request)) {
        String rStr =
            new String(response.getEntity().getContent().readAllBytes(), StandardCharsets.UTF_8);
      }
    }
  }
}
