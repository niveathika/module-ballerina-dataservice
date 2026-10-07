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

import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.projects.ProjectKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.Location;

import java.nio.file.Path;
import java.util.HashSet;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_101;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_102;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_103;

/**
 * Validates the usage of the `@dataservice:Expose` annotation.
 */
public class ExposeAnnotationValidator implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String ORG_NAME = "ballerina";
    private static final String MODULE_NAME = "dataservice";
    private static final String EXPOSE_ANNOTATION = "Expose";
    private static final String OPERATIONS_FIELD = "operations";
    private static final String PERSIST_DIRECTORY = "persist";

    @Override
    public void perform(SyntaxNodeAnalysisContext ctx) {
        TypeDefinitionNode typeDefinition = (TypeDefinitionNode) ctx.node();
        if (typeDefinition.metadata().isEmpty()) {
            return;
        }
        for (AnnotationNode annotation : typeDefinition.metadata().get().annotations()) {
            if (!isExposeAnnotation(ctx, annotation)) {
                continue;
            }
            if (typeDefinition.typeDescriptor().kind() != SyntaxKind.RECORD_TYPE_DESC || !isPersistModel(ctx)) {
                report(ctx, DATASERVICE_101, annotation.location());
                continue;
            }
            validateOperations(ctx, annotation);
        }
    }

    private static boolean isExposeAnnotation(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation) {
        Optional<Symbol> symbol = ctx.semanticModel().symbol(annotation);
        if (symbol.isEmpty() || !(symbol.get() instanceof AnnotationSymbol annotationSymbol)) {
            return false;
        }
        Optional<ModuleSymbol> module = annotationSymbol.getModule();
        return module.isPresent() && ORG_NAME.equals(module.get().id().orgName())
                && MODULE_NAME.equals(module.get().id().moduleName())
                && annotationSymbol.getName().map(EXPOSE_ANNOTATION::equals).orElse(false);
    }

    // A persist model is compiled as a single file, either persist/model.bal or persist/<model>/model.bal.
    private static boolean isPersistModel(SyntaxNodeAnalysisContext ctx) {
        try {
            if (ctx.currentPackage().project().kind() != ProjectKind.SINGLE_FILE_PROJECT) {
                return false;
            }
            Path folder = ctx.currentPackage().project().sourceRoot().toAbsolutePath().getParent();
            for (int level = 0; level < 2 && folder != null; level++) {
                Path folderName = folder.getFileName();
                if (folderName != null && PERSIST_DIRECTORY.equals(folderName.toString())) {
                    return true;
                }
                folder = folder.getParent();
            }
        } catch (UnsupportedOperationException e) {
            return false;
        }
        return false;
    }

    private static void validateOperations(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation) {
        if (annotation.annotValue().isEmpty()) {
            return;
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (!(field instanceof SpecificFieldNode specificField)
                    || !OPERATIONS_FIELD.equals(specificField.fieldName().toSourceCode().trim())
                    || specificField.valueExpr().isEmpty()) {
                continue;
            }
            // Only a list constructor can be checked here; a constant reference is checked by the persist tool.
            ExpressionNode value = specificField.valueExpr().get();
            if (!(value instanceof ListConstructorExpressionNode list)) {
                continue;
            }
            if (list.expressions().isEmpty()) {
                report(ctx, DATASERVICE_102, value.location());
                continue;
            }
            Set<String> seen = new HashSet<>();
            for (Node member : list.expressions()) {
                Optional<String> operation = operationValue(member);
                if (operation.isPresent() && !seen.add(operation.get())) {
                    report(ctx, DATASERVICE_103, member.location(), operation.get());
                }
            }
        }
    }

    // Enum member names are the upper-case form of their values, so `READ` and `"read"` are the same operation.
    private static Optional<String> operationValue(Node member) {
        if (member instanceof QualifiedNameReferenceNode reference) {
            return Optional.of(reference.identifier().text().trim().toLowerCase(Locale.ROOT));
        }
        if (member instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.STRING_LITERAL) {
            String text = literal.literalToken().text().trim();
            return Optional.of(text.substring(1, text.length() - 1));
        }
        return Optional.empty();
    }

    private static void report(SyntaxNodeAnalysisContext ctx, DiagnosticCodes code, Location location,
                               Object... args) {
        DiagnosticInfo info = new DiagnosticInfo(code.getCode(), code.getMessage(), code.getSeverity());
        ctx.reportDiagnostic(DiagnosticFactory.createDiagnostic(info, location, args));
    }
}
