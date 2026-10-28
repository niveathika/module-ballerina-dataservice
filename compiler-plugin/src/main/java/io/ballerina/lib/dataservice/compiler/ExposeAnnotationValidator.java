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
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.EnumDeclarationNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
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

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_101;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_102;

/**
 * Validates the `@dataservice:Expose` annotations of a persist model.
 */
public class ExposeAnnotationValidator implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String ORG_NAME = "ballerina";
    private static final String MODULE_NAME = "dataservice";
    private static final String EXPOSE_ANNOTATION = "Expose";
    private static final String OPERATIONS_FIELD = "operations";
    private static final String PERSIST_DIRECTORY = "persist";
    private static final String BALLERINA_TOML = "Ballerina.toml";
    private static final Set<String> OPERATIONS = Set.of("read", "create", "update", "delete");

    @Override
    public void perform(SyntaxNodeAnalysisContext ctx) {
        Node node = ctx.node();
        Optional<MetadataNode> metadata = switch (node.kind()) {
            case TYPE_DEFINITION -> ((TypeDefinitionNode) node).metadata();
            case ENUM_DECLARATION -> ((EnumDeclarationNode) node).metadata();
            case CLASS_DEFINITION -> ((ClassDefinitionNode) node).metadata();
            default -> Optional.empty();
        };
        if (metadata.isEmpty() || !isPersistModel(ctx)) {
            return;
        }
        for (AnnotationNode annotation : metadata.get().annotations()) {
            if (!isExposeAnnotation(ctx.semanticModel().symbol(annotation))) {
                continue;
            }
            if (node instanceof TypeDefinitionNode type
                    && type.typeDescriptor().kind() == SyntaxKind.RECORD_TYPE_DESC) {
                reportDuplicates(ctx, annotation, type.typeName().text().trim());
            } else {
                report(ctx, DATASERVICE_101, annotation.location());
            }
        }
    }

    // Matches persist's own rule: persist/<file> or persist/<model>/<file> of a package.
    static boolean isPersistModel(SyntaxNodeAnalysisContext ctx) {
        try {
            if (ctx.currentPackage().project().kind() != ProjectKind.SINGLE_FILE_PROJECT) {
                return false;
            }
            Path folder = ctx.currentPackage().project().sourceRoot().toAbsolutePath().getParent();
            for (int level = 0; level < 2 && folder != null; level++) {
                Path name = folder.getFileName();
                Path packageRoot = folder.getParent();
                if (name != null && PERSIST_DIRECTORY.equals(name.toString()) && packageRoot != null) {
                    return Files.isRegularFile(packageRoot.resolve(BALLERINA_TOML));
                }
                folder = packageRoot;
            }
        } catch (UnsupportedOperationException e) {
            return false;
        }
        return false;
    }

    private static boolean isExposeAnnotation(Optional<? extends Symbol> symbol) {
        return isAnnotation(symbol, ORG_NAME, MODULE_NAME, EXPOSE_ANNOTATION);
    }

    static boolean isAnnotation(Optional<? extends Symbol> symbol, String org, String module, String name) {
        if (symbol.isEmpty() || !(symbol.get() instanceof AnnotationSymbol annotationSymbol)) {
            return false;
        }
        Optional<ModuleSymbol> moduleSymbol = annotationSymbol.getModule();
        return moduleSymbol.isPresent() && org.equals(moduleSymbol.get().id().orgName())
                && module.equals(moduleSymbol.get().id().moduleName())
                && annotationSymbol.getName().map(name::equals).orElse(false);
    }

    // The actions an Expose annotation allows, every action when it gives no list.
    static Set<String> exposedOperations(SyntaxNodeAnalysisContext ctx, MetadataNode metadata) {
        for (AnnotationNode annotation : metadata.annotations()) {
            if (!isExposeAnnotation(ctx.semanticModel().symbol(annotation))) {
                continue;
            }
            if (annotation.annotValue().isEmpty()) {
                return OPERATIONS;
            }
            for (MappingFieldNode field : annotation.annotValue().get().fields()) {
                if (field instanceof SpecificFieldNode specificField
                        && OPERATIONS_FIELD.equals(specificField.fieldName().toSourceCode().trim())
                        && specificField.valueExpr().isPresent()
                        && specificField.valueExpr().get() instanceof ListConstructorExpressionNode list) {
                    Set<String> operations = new HashSet<>();
                    list.expressions().forEach(member -> operationValue(member).ifPresent(operations::add));
                    return operations;
                }
            }
            return OPERATIONS;
        }
        return Set.of();
    }

    private static void reportDuplicates(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation, String entity) {
        if (annotation.annotValue().isEmpty()) {
            return;
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (!(field instanceof SpecificFieldNode specificField)
                    || !OPERATIONS_FIELD.equals(specificField.fieldName().toSourceCode().trim())
                    || specificField.valueExpr().isEmpty()
                    || !(specificField.valueExpr().get() instanceof ListConstructorExpressionNode list)) {
                continue;
            }
            Set<String> seen = new HashSet<>();
            for (Node member : list.expressions()) {
                Optional<String> operation = operationValue(member);
                if (operation.isPresent() && !seen.add(operation.get())) {
                    report(ctx, DATASERVICE_102, member.location(), member.toSourceCode().trim(), entity);
                }
            }
        }
    }

    // Other forms are not operations; the compiler reports them through the annotation's type.
    private static Optional<String> operationValue(Node member) {
        if (member instanceof QualifiedNameReferenceNode reference) {
            String value = reference.identifier().text().trim().toLowerCase(Locale.ROOT);
            return OPERATIONS.contains(value) ? Optional.of(value) : Optional.empty();
        }
        if (member instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.STRING_LITERAL) {
            String text = literal.literalToken().text();
            return Optional.of(text.substring(1, text.length() - 1));
        }
        return Optional.empty();
    }

    static void report(SyntaxNodeAnalysisContext ctx, DiagnosticCodes code, Location location,
                               Object... args) {
        DiagnosticInfo info = new DiagnosticInfo(code.getCode(), code.getMessage(), code.getSeverity());
        ctx.reportDiagnostic(DiagnosticFactory.createDiagnostic(info, location, args));
    }
}
