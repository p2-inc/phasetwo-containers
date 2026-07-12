///usr/bin/env jbang "$0" "$@" ; exit $?
//DEPS org.kohsuke:github-api:2.0-rc.6

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.kohsuke.github.GHCompare;
import org.kohsuke.github.GHPullRequest;
import org.kohsuke.github.GHRepository;
import org.kohsuke.github.GitHub;
import org.kohsuke.github.GitHubBuilder;

/**
 * Builds the "component updates in this PR" comment body for a
 * phasetwo-containers PR that bumps libs/pom.xml component versions: the list
 * of downstream PRs that shipped between the old and new version of each
 * changed component.
 *
 * <p>This only computes and prints the comment body to stdout (or the literal
 * {@link #NO_CHANGES} sentinel if no tracked component changed) — it never
 * writes to GitHub. It's meant to run from a plain {@code pull_request}
 * workflow, whose token is read-only for fork PRs; a separate
 * {@code workflow_run}-triggered workflow with write access is responsible
 * for actually posting the comment.
 *
 * <p>Usage: ComponentDigest.java <old-pom-path> <new-pom-path> <owner/repo>
 * <base-sha> <head-sha>
 */
public class ComponentDigest {

  static final String MARKER = "<!-- component-pr-digest -->";
  static final String NO_CHANGES = "NO_CHANGES";

  // property name in libs/pom.xml -> component's GitHub repo. Tags in that
  // repo are expected to be "v<version>". Unknown properties are ignored.
  static final Map<String, String> COMPONENT_REPOS =
      Map.ofEntries(
          Map.entry("keycloak-events.version", "p2-inc/keycloak-events"),
          Map.entry("keycloak-magic-link.version", "p2-inc/keycloak-magic-link"),
          Map.entry("keycloak-orgs.version", "p2-inc/keycloak-orgs"),
          Map.entry("keycloak-scim-server.version", "p2-inc/keycloak-scim-server"),
          Map.entry("keycloak-themes.version", "p2-inc/keycloak-themes"),
          Map.entry("phasetwo-admin-portal.version", "p2-inc/phasetwo-admin-portal"),
          Map.entry("phasetwo-idp-wizard.version", "p2-inc/idp-wizard"));

  public static void main(String[] args) throws IOException {
    if (args.length != 5) {
      System.err.println(
          "usage: ComponentDigest.java <old-pom> <new-pom> <owner/repo> <base-sha> <head-sha>");
      System.exit(1);
    }
    String oldPom = Files.readString(Path.of(args[0]));
    String newPom = Files.readString(Path.of(args[1]));
    String thisRepo = args[2];
    String baseSha = args[3];
    String headSha = args[4];

    GitHub gh = new GitHubBuilder().withOAuthToken(System.getenv("GITHUB_TOKEN")).build();

    List<String> sections = new ArrayList<>();
    for (Map.Entry<String, String> entry : COMPONENT_REPOS.entrySet()) {
      String propertyKey = entry.getKey();
      String repoName = entry.getValue();
      String oldVersion = extractVersion(oldPom, propertyKey);
      String newVersion = extractVersion(newPom, propertyKey);
      if (oldVersion == null || newVersion == null || oldVersion.equals(newVersion)) {
        continue;
      }
      sections.add(digestSection(gh, propertyKey, repoName, oldVersion, newVersion));
    }

    if (sections.isEmpty()) {
      System.out.println(NO_CHANGES);
      return;
    }

    String updatedAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString();
    String shortBase = baseSha.substring(0, Math.min(7, baseSha.length()));
    String shortHead = headSha.substring(0, Math.min(7, headSha.length()));
    String compareUrl =
        String.format("https://github.com/%s/compare/%s...%s", thisRepo, baseSha, headSha);

    StringBuilder body = new StringBuilder();
    body.append(MARKER).append("\n");
    body.append("## Component updates in this PR\n\n");
    body.append(
        String.format(
            "_Auto-generated, updates on every push to this PR. Last updated %s from"
                + " [`%s...%s`](%s)._%n%n",
            updatedAt, shortBase, shortHead, compareUrl));
    for (String section : sections) {
      body.append(section).append("\n");
    }

    System.out.println(body);
  }

  static String extractVersion(String pom, String propertyKey) {
    Pattern p =
        Pattern.compile(
            "<" + Pattern.quote(propertyKey) + ">([^<]*)</" + Pattern.quote(propertyKey) + ">");
    Matcher m = p.matcher(pom);
    return m.find() ? m.group(1).trim() : null;
  }

  static String digestSection(
      GitHub gh, String propertyKey, String repoName, String oldVersion, String newVersion) {
    String component = propertyKey.substring(0, propertyKey.length() - ".version".length());
    String oldTag = "v" + oldVersion;
    String newTag = "v" + newVersion;
    String header =
        String.format(
            "### %s: `%s` → `%s` ([%s](https://github.com/%s))%n",
            component, oldVersion, newVersion, repoName, repoName);

    try {
      GHRepository repo = gh.getRepository(repoName);
      GHCompare compare = repo.getCompare(oldTag, newTag);

      LinkedHashMap<Integer, GHPullRequest> prs = new LinkedHashMap<>();
      for (GHCompare.Commit commit : compare.getCommits()) {
        for (GHPullRequest pr : commit.listPullRequests()) {
          prs.putIfAbsent(pr.getNumber(), pr);
        }
      }

      if (prs.isEmpty()) {
        return header
            + String.format("- _no pull requests found; [compare](%s)_%n", compare.getHtmlUrl());
      }

      StringBuilder sb = new StringBuilder(header);
      prs.values().stream()
          .sorted(Comparator.comparingInt(GHPullRequest::getNumber))
          .forEach(
              pr ->
                  sb.append(
                      String.format(
                          "- [#%d](%s) %s%n", pr.getNumber(), pr.getHtmlUrl(), pr.getTitle())));
      return sb.toString();
    } catch (IOException e) {
      return header
          + String.format(
              "- _couldn't diff `%s...%s` (%s); see [compare](https://github.com/%s/compare/%s...%s)_%n",
              oldTag, newTag, e.getMessage(), repoName, oldTag, newTag);
    }
  }
}
