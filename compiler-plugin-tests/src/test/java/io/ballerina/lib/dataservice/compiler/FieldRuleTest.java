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
        List<Diagnostic> diagnostics = diagnostics("rules_valid");
        Assert.assertEquals(ofSeverity(diagnostics, DiagnosticSeverity.ERROR), List.of());
        Assert.assertEquals(ofSeverity(diagnostics, DiagnosticSeverity.WARNING), List.of());
    }

    @Test(dataProvider = "errors")
    public void testError(String project, String code, String message, int line) {
        List<Diagnostic> errors = ofSeverity(diagnostics(project), DiagnosticSeverity.ERROR);
        Assert.assertEquals(errors.size(), 1, errors.toString());
        Assert.assertEquals(errors.get(0).diagnosticInfo().code(), code);
        Assert.assertEquals(errors.get(0).message(), message);
        Assert.assertEquals(errors.get(0).location().lineRange().startLine().line() + 1, line);
    }

    @DataProvider
    public Object[][] errors() {
        return new Object[][]{
                {"rule_multiple", "DATASERVICE_103", "the field 'name' of the entity 'Employee' has more than one " +
                        "of @dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal. Keep one.", 8},
                {"rule_key", "DATASERVICE_104",
                        "the key field 'id' of the entity 'Employee' cannot have @dataservice:Immutable.", 6},
                {"rule_needs_value", "DATASERVICE_105", "the field 'name' of the entity 'Employee' needs a " +
                        "'value' in @dataservice:Internal.", 7},
                {"rule_value_type", "DATASERVICE_106", "the 'value' in @dataservice:ReadOnly of the field 'name' " +
                        "of the entity 'Employee' is not a 'string'.", 7},
                {"rule_value_hex", "DATASERVICE_106", "the 'value' in @dataservice:ReadOnly of the field 'hours' " +
                        "of the entity 'Item' is not a 'decimal'.", 7},
                {"rule_relation_field", "DATASERVICE_107", "@dataservice:Immutable cannot be used on the " +
                        "relation field 'department' of the entity 'Employee'. Use it on the foreign key field, " +
                        "declared with @sql:Relation.", 7},
                {"rule_no_foreign_key", "DATASERVICE_107", "@dataservice:ReadOnly cannot be used on the relation " +
                        "field 'employees' of the entity 'Department'. Use it on the foreign key field, declared " +
                        "with @sql:Relation.", 14},
                {"rule_foreign_key_mixed", "DATASERVICE_108", "the foreign key fields of the relation 'slot' of " +
                        "the entity 'Employee' must have the same field rule.", 8},
                {"rule_one_to_one", "DATASERVICE_112", "@dataservice:ReadOnly cannot be used on the field " +
                        "'employeeId' of the entity 'Profile', the foreign key of a one-to-one relation. Remove it.",
                        8},
        };
    }

    @Test
    public void testNoEffectWarning() {
        List<Diagnostic> diagnostics = diagnostics("rule_no_effect");
        Assert.assertEquals(ofSeverity(diagnostics, DiagnosticSeverity.ERROR), List.of());
        List<Diagnostic> warnings = ofSeverity(diagnostics, DiagnosticSeverity.WARNING);
        Assert.assertEquals(warnings.size(), 1, warnings.toString());
        Assert.assertEquals(warnings.get(0).diagnosticInfo().code(), "DATASERVICE_109");
        Assert.assertEquals(warnings.get(0).message(), "@dataservice:ReadOnly on the field 'name' of the entity " +
                "'Employee' has no effect. Remove it, or add 'create' or 'update' to 'operations'.");
    }

    @Test
    public void testRelationNoEffectWarning() {
        List<Diagnostic> diagnostics = diagnostics("rule_relation_no_effect");
        Assert.assertEquals(ofSeverity(diagnostics, DiagnosticSeverity.ERROR), List.of());
        List<Diagnostic> warnings = ofSeverity(diagnostics, DiagnosticSeverity.WARNING);
        Assert.assertEquals(warnings.size(), 1, warnings.toString());
        Assert.assertEquals(warnings.get(0).diagnosticInfo().code(), "DATASERVICE_109");
        Assert.assertEquals(warnings.get(0).message(), "@dataservice:Internal on the field 'department' of the " +
                "entity 'Employee' has no effect. Remove it, or add 'read' to 'operations'.");
    }

    private static List<Diagnostic> diagnostics(String project) {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        Project loaded = SingleFileProject.load(ProjectEnvironmentBuilder.getBuilder(environment),
                RESOURCE_DIRECTORY.resolve(project).resolve("persist").resolve("model.bal"));
        return List.copyOf(loaded.currentPackage().getCompilation().diagnosticResult().diagnostics());
    }

    private static List<Diagnostic> ofSeverity(List<Diagnostic> diagnostics, DiagnosticSeverity severity) {
        return diagnostics.stream().filter(diagnostic -> diagnostic.diagnosticInfo().severity() == severity).toList();
    }
}
