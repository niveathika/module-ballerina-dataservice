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

import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.EnumDeclarationNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_101;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_102;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_110;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_111;
import static io.ballerina.lib.dataservice.compiler.PluginUtils.MODULE_NAME;
import static io.ballerina.lib.dataservice.compiler.PluginUtils.ORG_NAME;
import static io.ballerina.lib.dataservice.compiler.PluginUtils.fieldName;
import static io.ballerina.lib.dataservice.compiler.PluginUtils.isAnnotation;
import static io.ballerina.lib.dataservice.compiler.PluginUtils.report;

/**
 * Validates the `@dataservice:Expose` annotations of a persist model.
 */
final class ExposeAnnotationValidator {

    private static final String EXPOSE_ANNOTATION = "Expose";
    private static final String OPERATIONS_FIELD = "operations";
    private static final String SCOPES_FIELD = "scopes";
    private static final Set<String> OPERATIONS = Set.of("read", "create", "update", "delete");

    private ExposeAnnotationValidator() {
    }

    // Returns the operations the member's first Expose annotation allows, none when it has no Expose annotation.
    static Set<String> validate(SyntaxNodeAnalysisContext ctx, Node member) {
        Optional<MetadataNode> metadata = switch (member.kind()) {
            case TYPE_DEFINITION -> ((TypeDefinitionNode) member).metadata();
            case ENUM_DECLARATION -> ((EnumDeclarationNode) member).metadata();
            case CLASS_DEFINITION -> ((ClassDefinitionNode) member).metadata();
            default -> Optional.empty();
        };
        if (metadata.isEmpty()) {
            return Set.of();
        }
        List<AnnotationNode> exposes = metadata.get().annotations().stream()
                .filter(annotation -> isExposeAnnotation(ctx.semanticModel().symbol(annotation)))
                .toList();
        if (exposes.isEmpty()) {
            return Set.of();
        }
        Set<String> operations = exposedOperations(exposes.get(0));
        for (AnnotationNode annotation : exposes) {
            if (member instanceof TypeDefinitionNode type
                    && type.typeDescriptor().kind() == SyntaxKind.RECORD_TYPE_DESC) {
                String entity = type.typeName().text().trim();
                reportDuplicates(ctx, annotation, entity);
                reportInvalidScopes(ctx, annotation, operations, entity);
            } else {
                report(ctx, DATASERVICE_101, annotation.location());
            }
        }
        return operations;
    }

    private static boolean isExposeAnnotation(Optional<? extends Symbol> symbol) {
        return isAnnotation(symbol, ORG_NAME, MODULE_NAME, EXPOSE_ANNOTATION);
    }

    // The actions an Expose annotation allows, every action when it gives no list.
    private static Set<String> exposedOperations(AnnotationNode annotation) {
        if (annotation.annotValue().isEmpty()) {
            return OPERATIONS;
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (field instanceof SpecificFieldNode specificField
                    && OPERATIONS_FIELD.equals(fieldName(specificField))
                    && specificField.valueExpr().isPresent()
                    && specificField.valueExpr().get() instanceof ListConstructorExpressionNode list) {
                Set<String> operations = new HashSet<>();
                list.expressions().forEach(member -> operationValue(member).ifPresent(operations::add));
                return operations;
            }
        }
        return OPERATIONS;
    }

    private static void reportDuplicates(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation, String entity) {
        if (annotation.annotValue().isEmpty()) {
            return;
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (!(field instanceof SpecificFieldNode specificField)
                    || !OPERATIONS_FIELD.equals(fieldName(specificField))
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

    private static void reportInvalidScopes(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation,
                                            Set<String> operations, String entity) {
        if (annotation.annotValue().isEmpty()) {
            return;
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (!(field instanceof SpecificFieldNode specificField)
                    || !SCOPES_FIELD.equals(fieldName(specificField))
                    || specificField.valueExpr().isEmpty()
                    || !(specificField.valueExpr().get() instanceof MappingConstructorExpressionNode scopes)) {
                continue;
            }
            for (MappingFieldNode actionField : scopes.fields()) {
                if (!(actionField instanceof SpecificFieldNode action)) {
                    continue;
                }
                String name = fieldName(action);
                if (!operations.contains(name)) {
                    report(ctx, DATASERVICE_111, action.fieldName().location(), entity, name);
                }
                if (action.valueExpr().isPresent()
                        && action.valueExpr().get() instanceof ListConstructorExpressionNode list) {
                    for (Node member : list.expressions()) {
                        if (member instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.STRING_LITERAL) {
                            String text = literal.literalToken().text();
                            String scope = text.substring(1, text.length() - 1);
                            if (scope.isEmpty() || scope.chars().anyMatch(Character::isWhitespace)) {
                                report(ctx, DATASERVICE_110, member.location(), scope, entity);
                            }
                        }
                    }
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
}
