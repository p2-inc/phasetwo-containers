package io.phasetwo.containers.hibernate;

import org.hibernate.boot.model.FunctionContributions;
import org.hibernate.boot.model.FunctionContributor;
import org.hibernate.query.sqm.function.SqmFunctionRegistry;
import com.google.auto.service.AutoService;
import lombok.extern.jbosslog.JBossLog;

@JBossLog
@AutoService(FunctionContributor.class)
public class LikeEscapeFunctionContributor implements FunctionContributor {
  @Override
  public void contributeFunctions(FunctionContributions contributions) {
    log.infof("contribute function for like_escape to (?1 LIKE ?2 ESCAPE ?3)");
    SqmFunctionRegistry registry = contributions.getFunctionRegistry();
    registry.registerPattern(
        "like_escape",
        "(?1 LIKE ?2 ESCAPE ?3)");
  }
}
