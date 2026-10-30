/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.dataservice.compiler;

import io.ballerina.projects.Project;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.SingleFileProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import org.testng.Assert;
import org.testng.annotations.DataProvider;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Tests the validation of the field rules `@dataservice:ReadOnly`, `@dataservice:Immutable` and
 * `@dataservice:Internal`.
 */
public class FieldRuleTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "projects")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();

    @Test
    public void testValidRules() {
        Assert.assertEquals(diagnostics("rules_valid", DiagnosticSeverity.ERROR), List.of());
        Assert.assertEquals(diagnostics("rules_valid", DiagnosticSeverity.WARNING), List.of());
    }

    @Test(dataProvider = "errors")
    public void testError(String project, String code, String message) {
        List<Diagnostic> errors = diagnostics(project, DiagnosticSeverity.ERROR);
        Assert.assertEquals(errors.size(), 1, errors.toString());
        Assert.assertEquals(errors.get(0).diagnosticInfo().code(), code);
        Assert.assertEquals(errors.get(0).message(), message);
    }

    @DataProvider
    public Object[][] errors() {
        return new Object[][]{
                {"rule_multiple", "DATASERVICE_103", "the field 'name' of the entity 'Employee' has more than one " +
                        "of @dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal."},
                {"rule_key", "DATASERVICE_104",
                        "the key field 'id' of the entity 'Employee' cannot have @dataservice:Immutable."},
                {"rule_needs_value", "DATASERVICE_105", "the field 'name' of the entity 'Employee' needs a " +
                        "'value' in @dataservice:Internal, because it is neither nullable nor generated."},
                {"rule_value_type", "DATASERVICE_106", "the 'value' in @dataservice:ReadOnly of the field 'name' " +
                        "of the entity 'Employee' is not a 'string'."},
                {"rule_relation_field", "DATASERVICE_107", "@dataservice:Immutable cannot be used on the " +
                        "relation field 'department' of the entity 'Employee'. Use it on the foreign key field, " +
                        "declared with @sql:Relation."},
                {"rule_no_foreign_key", "DATASERVICE_107", "@dataservice:ReadOnly cannot be used on the relation " +
                        "field 'employees' of the entity 'Department'. Use it on the foreign key field, declared " +
                        "with @sql:Relation."},
                {"rule_foreign_key_mixed", "DATASERVICE_108", "the foreign key fields of the relation 'slot' of " +
                        "the entity 'Employee' must have the same field rule."},
                {"rule_one_to_one", "DATASERVICE_112", "@dataservice:ReadOnly cannot be used on the foreign key " +
                        "field 'employeeId' of the entity 'Profile', because its relation is one to one and every " +
                        "create would set the same value."},
        };
    }

    @Test
    public void testNoEffectWarning() {
        Assert.assertEquals(diagnostics("rule_no_effect", DiagnosticSeverity.ERROR), List.of());
        List<Diagnostic> warnings = diagnostics("rule_no_effect", DiagnosticSeverity.WARNING);
        Assert.assertEquals(warnings.size(), 1, warnings.toString());
        Assert.assertEquals(warnings.get(0).diagnosticInfo().code(), "DATASERVICE_109");
        Assert.assertEquals(warnings.get(0).message(), "@dataservice:ReadOnly on the field 'name' of the entity " +
                "'Employee' has no effect, because the entity does not allow 'create' or 'update'.");
    }

    @Test
    public void testRelationNoEffectWarning() {
        Assert.assertEquals(diagnostics("rule_relation_no_effect", DiagnosticSeverity.ERROR), List.of());
        List<Diagnostic> warnings = diagnostics("rule_relation_no_effect", DiagnosticSeverity.WARNING);
        Assert.assertEquals(warnings.size(), 1, warnings.toString());
        Assert.assertEquals(warnings.get(0).diagnosticInfo().code(), "DATASERVICE_109");
        Assert.assertEquals(warnings.get(0).message(), "@dataservice:Internal on the field 'department' of the " +
                "entity 'Employee' has no effect, because the entity does not allow 'read'.");
    }

    private static List<Diagnostic> diagnostics(String project, DiagnosticSeverity severity) {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        Project loaded = SingleFileProject.load(ProjectEnvironmentBuilder.getBuilder(environment),
                RESOURCE_DIRECTORY.resolve(project).resolve("persist").resolve("model.bal"));
        return loaded.currentPackage().getCompilation().diagnosticResult().diagnostics().stream()
                .filter(diagnostic -> diagnostic.diagnosticInfo().severity() == severity)
                .toList();
    }
}
