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
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.directory.SingleFileProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Tests the validation of the `@dataservice:Expose` annotation.
 */
public class ExposeAnnotationTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "projects")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    private static final String PLACEMENT_MESSAGE =
            "the @dataservice:Expose annotation is allowed only on a record type in the persist model.";

    @Test
    public void testValidModel() {
        Assert.assertEquals(errors(loadModel("valid", "persist", "model.bal")), List.of());
    }

    @Test
    public void testNonRecordType() {
        assertDiagnostic(errors(loadModel("non_record", "persist", "model.bal")), "DATASERVICE_101",
                PLACEMENT_MESSAGE, 3);
    }

    @Test
    public void testEnum() {
        assertDiagnostic(errors(loadModel("enum_type", "persist", "model.bal")), "DATASERVICE_101",
                PLACEMENT_MESSAGE, 3);
    }

    @Test
    public void testDuplicateOperation() {
        assertDiagnostic(errors(loadModel("duplicate_operations", "persist", "model.bal")), "DATASERVICE_102",
                "duplicate operation '\"read\"' in the @dataservice:Expose annotation of the entity 'Department'. " +
                        "Remove the duplicate.", 3);
    }

    @Test
    public void testDuplicateOperationReportedPerRepeat() {
        List<Diagnostic> errors = errors(loadModel("duplicate_qualified", "persist", "model.bal"));
        Assert.assertEquals(errors.size(), 2, errors.toString());
        for (Diagnostic error : errors) {
            Assert.assertEquals(error.diagnosticInfo().code(), "DATASERVICE_102");
            Assert.assertEquals(error.message(), "duplicate operation 'dataservice:CREATE' in the " +
                    "@dataservice:Expose annotation of the entity 'Department'. Remove the duplicate.");
        }
    }

    @Test
    public void testInvalidScope() {
        List<Diagnostic> errors = errors(loadModel("scope_invalid", "persist", "model.bal"));
        Assert.assertEquals(errors.stream().map(Diagnostic::message).toList(), List.of(
                "invalid scope '' in the @dataservice:Expose annotation of the entity 'Department'. A scope " +
                        "must be a non-empty string without whitespace.",
                "invalid scope 'hr admin' in the @dataservice:Expose annotation of the entity 'Department'. A " +
                        "scope must be a non-empty string without whitespace."));
        Assert.assertTrue(errors.stream().allMatch(error -> error.diagnosticInfo().code().equals("DATASERVICE_110")));
    }

    @Test
    public void testScopesForAnActionNotEnabled() {
        assertDiagnostic(errors(loadModel("scope_not_enabled", "persist", "model.bal")), "DATASERVICE_111",
                "the @dataservice:Expose annotation of the entity 'Department' sets scopes for 'delete', which is " +
                        "not in 'operations'. Add it to 'operations', or remove its scopes.", 3);
    }

    @Test
    public void testQuotedScopeKeys() {
        assertDiagnostic(errors(loadModel("scopes_quoted", "persist", "model.bal")), "DATASERVICE_111",
                "the @dataservice:Expose annotation of the entity 'Department' sets scopes for 'update', which is " +
                        "not in 'operations'. Add it to 'operations', or remove its scopes.", 5);
    }

    @Test
    public void testValidScopes() {
        Assert.assertTrue(errors(loadModel("scopes_valid", "persist", "model.bal")).isEmpty());
    }

    @Test
    public void testEmptyOperationsRejectedByType() {
        List<Diagnostic> errors = errors(loadModel("empty_operations", "persist", "model.bal"));
        Assert.assertEquals(errors.size(), 1, errors.toString());
        Assert.assertTrue(errors.get(0).message().startsWith("invalid usage of list constructor"),
                errors.get(0).message());
    }

    @Test
    public void testUnknownOperationRejectedByType() {
        List<Diagnostic> errors = errors(loadModel("unknown_operation", "persist", "model.bal"));
        Assert.assertEquals(errors.size(), 1, errors.toString());
        Assert.assertTrue(errors.get(0).message().startsWith("incompatible types"), errors.get(0).message());
    }

    @Test
    public void testNamedModel() {
        assertDiagnostic(errors(loadModel("named_model", "persist", "hr", "model.bal")), "DATASERVICE_102",
                "duplicate operation '\"read\"' in the @dataservice:Expose annotation of the entity 'Department'. " +
                        "Remove the duplicate.", 3);
    }

    @Test
    public void testPersistDirectoryOutsidePackage() {
        Assert.assertEquals(errors(loadModel("no_package", "persist", "model.bal")), List.of());
    }

    @Test
    public void testSingleFileOutsidePersistDirectory() {
        Assert.assertEquals(errors(loadModel("outside_persist", "models", "model.bal")), List.of());
    }

    @Test
    public void testPackageSource() {
        Project project = BuildProject.load(environmentBuilder(), RESOURCE_DIRECTORY.resolve("regular_package"));
        Assert.assertEquals(errors(project), List.of());
    }

    private static ProjectEnvironmentBuilder environmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    private static Project loadModel(String first, String... more) {
        return SingleFileProject.load(environmentBuilder(), RESOURCE_DIRECTORY.resolve(Paths.get(first, more)));
    }

    private static List<Diagnostic> errors(Project project) {
        return project.currentPackage().getCompilation().diagnosticResult().diagnostics().stream()
                .filter(diagnostic -> diagnostic.diagnosticInfo().severity() == DiagnosticSeverity.ERROR)
                .toList();
    }

    private static void assertDiagnostic(List<Diagnostic> errors, String code, String message, int line) {
        Assert.assertEquals(errors.size(), 1, errors.toString());
        Diagnostic diagnostic = errors.get(0);
        Assert.assertEquals(diagnostic.diagnosticInfo().code(), code);
        Assert.assertEquals(diagnostic.message(), message);
        Assert.assertEquals(diagnostic.location().lineRange().startLine().line() + 1, line);
    }
}
