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

    @Test
    public void testValidModel() {
        Assert.assertEquals(errors(loadModel("valid", "persist", "model.bal")), List.of());
    }

    @Test
    public void testNamedModel() {
        Assert.assertEquals(errors(loadModel("named_model", "persist", "hr", "model.bal")), List.of());
    }

    @Test
    public void testEmptyOperations() {
        List<Diagnostic> errors = errors(loadModel("empty_operations", "persist", "model.bal"));
        assertDiagnostic(errors, "DATASERVICE_102",
                "the 'operations' of the 'Expose' annotation cannot be empty", 3);
    }

    @Test
    public void testDuplicateOperations() {
        List<Diagnostic> errors = errors(loadModel("duplicate_operations", "persist", "model.bal"));
        assertDiagnostic(errors, "DATASERVICE_103",
                "the operation 'read' is listed more than once in the 'Expose' annotation", 3);
    }

    @Test
    public void testNonRecordType() {
        List<Diagnostic> errors = errors(loadModel("non_record", "persist", "model.bal"));
        assertDiagnostic(errors, "DATASERVICE_101",
                "the 'Expose' annotation can only be used on an entity record type in a persist model", 3);
    }

    @Test
    public void testSingleFileOutsidePersistDirectory() {
        List<Diagnostic> errors = errors(loadModel("single_file_outside_persist", "model.bal"));
        assertDiagnostic(errors, "DATASERVICE_101",
                "the 'Expose' annotation can only be used on an entity record type in a persist model", 3);
    }

    @Test
    public void testPackageSource() {
        Project project = BuildProject.load(environmentBuilder(), RESOURCE_DIRECTORY.resolve("regular_package"));
        List<Diagnostic> errors = errors(project);
        assertDiagnostic(errors, "DATASERVICE_101",
                "the 'Expose' annotation can only be used on an entity record type in a persist model", 3);
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
