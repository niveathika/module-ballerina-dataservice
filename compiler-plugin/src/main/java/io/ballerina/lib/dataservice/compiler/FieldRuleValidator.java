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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.RecordFieldSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.ArrayTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.OptionalTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.RecordFieldNode;
import io.ballerina.compiler.syntax.tree.RecordFieldWithDefaultValueNode;
import io.ballerina.compiler.syntax.tree.RecordTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.SimpleNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.Token;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.compiler.syntax.tree.UnaryExpressionNode;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_103;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_104;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_105;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_106;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_107;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_108;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_109;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_112;

/**
 * Validates the field rules `@dataservice:ReadOnly`, `@dataservice:Immutable` and `@dataservice:Internal` of a
 * persist model.
 */
public class FieldRuleValidator implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String DATASERVICE_ORG = "ballerina";
    private static final String DATASERVICE_MODULE = "dataservice";
    private static final String SQL_ORG = "ballerinax";
    private static final String SQL_MODULE = "persist.sql";
    private static final List<String> RULES = List.of("ReadOnly", "Immutable", "Internal");
    private static final String IMMUTABLE = "Immutable";
    private static final String READ_ONLY = "ReadOnly";
    private static final String INTERNAL = "Internal";
    private static final Map<String, List<String>> AFFECTED = Map.of(
            READ_ONLY, List.of("create", "update"),
            IMMUTABLE, List.of("update"),
            INTERNAL, List.of("read", "create", "update"));

    @Override
    public void perform(SyntaxNodeAnalysisContext ctx) {
        if (!(ctx.node() instanceof TypeDefinitionNode type)
                || !(type.typeDescriptor() instanceof RecordTypeDescriptorNode record)
                || !ExposeAnnotationValidator.isPersistModel(ctx)) {
            return;
        }
        String entity = type.typeName().text().trim();
        Map<String, TypeDefinitionNode> entities = entities(ctx);
        Map<String, String> declaredKeys = declaredForeignKeys(ctx, record);
        Set<String> operations = type.metadata()
                .map(metadata -> ExposeAnnotationValidator.exposedOperations(ctx, metadata)).orElse(Set.of());
        Map<String, Integer> relationIndex = new HashMap<>();
        Map<String, Field> relationFields = new HashMap<>();
        Map<String, Integer> relationIndexes = new HashMap<>();
        Map<String, Optional<String>> keyRules = new HashMap<>();
        Map<String, AnnotationNode> keyAnnotations = new HashMap<>();
        for (Node node : record.fields()) {
            Optional<Field> field = Field.of(node);
            if (field.isEmpty()) {
                continue;
            }
            Optional<String> target = relationTarget(field.get().type(), entities);
            int index = target.map(name -> relationIndex.merge(name, 1, Integer::sum) - 1).orElse(-1);
            if (target.isPresent()) {
                relationFields.put(field.get().name(), field.get());
                relationIndexes.put(field.get().name(), index);
            }
            List<AnnotationNode> rules = new ArrayList<>();
            field.get().metadata().ifPresent(metadata -> metadata.annotations().forEach(annotation -> {
                if (ruleName(ctx, annotation).isPresent()) {
                    rules.add(annotation);
                }
            }));
            String name = field.get().name();
            if (declaredKeys.containsKey(name)) {
                keyRules.put(name, rules.size() == 1 ? ruleName(ctx, rules.get(0)) : Optional.empty());
                if (rules.size() == 1) {
                    keyAnnotations.put(name, rules.get(0));
                }
            }
            if (rules.isEmpty()) {
                continue;
            }
            if (rules.size() > 1) {
                report(ctx, DATASERVICE_103, rules.get(1), name, entity);
                continue;
            }
            AnnotationNode annotation = rules.get(0);
            String rule = ruleName(ctx, annotation).orElseThrow();
            if (field.get().key() && !(READ_ONLY.equals(rule) && hasSqlAnnotation(ctx, field.get(), "Generated"))) {
                report(ctx, DATASERVICE_104, annotation, name, entity, rule);
                continue;
            }
            List<String> affected = AFFECTED.get(rule);
            if (target.isPresent()) {
                if (!INTERNAL.equals(rule)) {
                    report(ctx, DATASERVICE_107, annotation, rule, name, entity);
                    continue;
                }
                affected = List.of("read");
            } else if (!checkValue(ctx, annotation, rule, field.get(), entity,
                    field.get().type() instanceof OptionalTypeDescriptorNode, value(annotation))) {
                continue;
            }
            if (!operations.isEmpty() && affected.stream().noneMatch(operations::contains)) {
                report(ctx, DATASERVICE_109, annotation, rule, name, entity, String.join("' or '", affected));
            }
        }
        checkForeignKeys(ctx, entity, entities, operations, declaredKeys, relationFields, relationIndexes, keyRules,
                keyAnnotations);
    }

    // The foreign key fields of a relation share one rule, and a one-to-one foreign key cannot be set by the service.
    private static void checkForeignKeys(SyntaxNodeAnalysisContext ctx, String entity,
                                         Map<String, TypeDefinitionNode> entities, Set<String> operations,
                                         Map<String, String> declaredKeys, Map<String, Field> relationFields,
                                         Map<String, Integer> relationIndexes, Map<String, Optional<String>> keyRules,
                                         Map<String, AnnotationNode> keyAnnotations) {
        Map<String, List<String>> byRelation = new LinkedHashMap<>();
        declaredKeys.forEach((key, relation) -> {
            if (keyRules.containsKey(key)) {
                byRelation.computeIfAbsent(relation, name -> new ArrayList<>()).add(key);
            }
        });
        byRelation.forEach((relation, keys) -> {
            if (keys.stream().map(keyRules::get).distinct().count() > 1) {
                keys.stream().filter(keyAnnotations::containsKey).findFirst().ifPresent(key ->
                        report(ctx, DATASERVICE_108, keyAnnotations.get(key), relation, entity));
                return;
            }
            Field relationField = relationFields.get(relation);
            if (relationField == null || !operations.contains("create")
                    || !isOneToOne(relationField, entity, entities, relationIndexes.get(relation))) {
                return;
            }
            for (String key : keys) {
                Optional<String> rule = keyRules.get(key);
                if (rule.isPresent() && (READ_ONLY.equals(rule.get()) || INTERNAL.equals(rule.get()))) {
                    report(ctx, DATASERVICE_112, keyAnnotations.get(key), rule.get(), key, entity);
                }
            }
        });
    }

    private static boolean checkValue(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation, String rule,
                                      Field field, String entity, boolean nullable, Optional<ExpressionNode> value) {
        if (value.isEmpty()) {
            if (!IMMUTABLE.equals(rule) && !nullable && !hasSqlAnnotation(ctx, field, "Generated")) {
                report(ctx, DATASERVICE_105, annotation, field.name(), entity, rule);
                return false;
            }
            return true;
        }
        Optional<TypeSymbol> fieldType = ctx.semanticModel().symbol(field.node())
                .flatMap(symbol -> symbol instanceof RecordFieldSymbol recordField
                        ? Optional.of(recordField.typeDescriptor()) : Optional.empty());
        if (fieldType.isPresent() && !isSubtype(ctx.semanticModel(), value.get(), fieldType.get())) {
            report(ctx, DATASERVICE_106, annotation, rule, field.name(), entity,
                    field.type().toSourceCode().trim());
            return false;
        }
        return true;
    }

    private static boolean isSubtype(SemanticModel model, ExpressionNode expression, TypeSymbol type) {
        Optional<TypeSymbol> valueType = model.typeOf(expression);
        if (valueType.isPresent() && valueType.get().subtypeOf(type)) {
            return true;
        }
        // The value is copied into the generated code as written, where a numeric literal takes the field's type.
        Optional<Token> literal = numericLiteral(expression);
        if (literal.isEmpty()) {
            return false;
        }
        String text = literal.get().text().trim().toLowerCase(Locale.ROOT);
        boolean integer = literal.get().kind() == SyntaxKind.DECIMAL_INTEGER_LITERAL_TOKEN
                || literal.get().kind() == SyntaxKind.HEX_INTEGER_LITERAL_TOKEN;
        boolean asFloat = integer || !text.endsWith("d");
        boolean asDecimal = integer || !text.endsWith("f");
        return (asFloat && model.types().FLOAT.subtypeOf(type)) || (asDecimal && model.types().DECIMAL.subtypeOf(type));
    }

    private static Optional<Token> numericLiteral(ExpressionNode expression) {
        ExpressionNode inner = expression instanceof UnaryExpressionNode unary
                && unary.unaryOperator().kind() == SyntaxKind.MINUS_TOKEN ? unary.expression() : expression;
        return inner instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.NUMERIC_LITERAL ?
                Optional.of(literal.literalToken()) : Optional.empty();
    }

    private static boolean isOneToOne(Field field, String entity, Map<String, TypeDefinitionNode> entities,
                                      int index) {
        if (field.type() instanceof ArrayTypeDescriptorNode) {
            return false;
        }
        TypeDefinitionNode related = entities.get(typeName(field.type()).orElseThrow());
        List<Field> back = new ArrayList<>();
        for (Node node : ((RecordTypeDescriptorNode) related.typeDescriptor()).fields()) {
            Field.of(node).filter(other -> entity.equals(typeName(other.type()).orElse(""))).ifPresent(back::add);
        }
        return index < back.size() && !(back.get(index).type() instanceof ArrayTypeDescriptorNode);
    }

    private static Optional<String> relationTarget(Node type, Map<String, TypeDefinitionNode> entities) {
        return typeName(type).filter(entities::containsKey);
    }

    private static Optional<String> typeName(Node type) {
        Node inner = type;
        if (inner instanceof OptionalTypeDescriptorNode optional) {
            inner = optional.typeDescriptor();
        } else if (inner instanceof ArrayTypeDescriptorNode array) {
            inner = array.memberTypeDesc();
        }
        return inner instanceof SimpleNameReferenceNode reference ?
                Optional.of(reference.name().text().trim()) : Optional.empty();
    }

    private static Map<String, TypeDefinitionNode> entities(SyntaxNodeAnalysisContext ctx) {
        Map<String, TypeDefinitionNode> entities = new HashMap<>();
        Node root = ctx.node();
        while (root.parent() != null) {
            root = root.parent();
        }
        if (root instanceof ModulePartNode module) {
            module.members().forEach(member -> {
                if (member instanceof TypeDefinitionNode type
                        && type.typeDescriptor() instanceof RecordTypeDescriptorNode) {
                    entities.put(type.typeName().text().trim(), type);
                }
            });
        }
        return entities;
    }

    // The foreign key fields declared with @sql:Relation, and the relation field each belongs to.
    private static Map<String, String> declaredForeignKeys(SyntaxNodeAnalysisContext ctx,
                                                           RecordTypeDescriptorNode record) {
        Map<String, String> keys = new HashMap<>();
        for (Node node : record.fields()) {
            Optional<Field> field = Field.of(node);
            if (field.isEmpty() || field.get().metadata().isEmpty()) {
                continue;
            }
            for (AnnotationNode annotation : field.get().metadata().get().annotations()) {
                if (!ExposeAnnotationValidator.isAnnotation(ctx.semanticModel().symbol(annotation), SQL_ORG,
                        SQL_MODULE, "Relation") || annotation.annotValue().isEmpty()) {
                    continue;
                }
                for (MappingFieldNode mappingField : annotation.annotValue().get().fields()) {
                    if (mappingField instanceof SpecificFieldNode specific
                            && "keys".equals(specific.fieldName().toSourceCode().trim())
                            && specific.valueExpr().isPresent()
                            && specific.valueExpr().get() instanceof ListConstructorExpressionNode list) {
                        list.expressions().forEach(key -> keys.put(unquote(key.toSourceCode().trim()),
                                field.get().name()));
                    }
                }
            }
        }
        return keys;
    }

    private static boolean hasSqlAnnotation(SyntaxNodeAnalysisContext ctx, Field field, String name) {
        return field.metadata().isPresent() && field.metadata().get().annotations().stream()
                .anyMatch(annotation -> ExposeAnnotationValidator.isAnnotation(
                        ctx.semanticModel().symbol(annotation), SQL_ORG, SQL_MODULE, name));
    }

    private static Optional<String> ruleName(SyntaxNodeAnalysisContext ctx, AnnotationNode annotation) {
        for (String rule : RULES) {
            if (ExposeAnnotationValidator.isAnnotation(ctx.semanticModel().symbol(annotation), DATASERVICE_ORG,
                    DATASERVICE_MODULE, rule)) {
                return Optional.of(rule);
            }
        }
        return Optional.empty();
    }

    private static Optional<ExpressionNode> value(AnnotationNode annotation) {
        if (annotation.annotValue().isEmpty()) {
            return Optional.empty();
        }
        for (MappingFieldNode field : annotation.annotValue().get().fields()) {
            if (field instanceof SpecificFieldNode specific && "value".equals(specific.fieldName().toSourceCode()
                    .trim()) && specific.valueExpr().isPresent()) {
                return specific.valueExpr();
            }
        }
        return Optional.empty();
    }

    private static String unquote(String text) {
        return text.length() >= 2 && text.startsWith("\"") && text.endsWith("\"") ?
                text.substring(1, text.length() - 1) : text;
    }

    private static void report(SyntaxNodeAnalysisContext ctx, DiagnosticCodes code, AnnotationNode annotation,
                               Object... args) {
        ExposeAnnotationValidator.report(ctx, code, annotation.location(), args);
    }

    private record Field(String name, boolean key, Node type, Optional<MetadataNode> metadata, Node node) {

        private static Optional<Field> of(Node node) {
            if (node instanceof RecordFieldNode field) {
                return Optional.of(new Field(field.fieldName().text().trim(), field.readonlyKeyword().isPresent(),
                        field.typeName(), field.metadata(), field));
            }
            if (node instanceof RecordFieldWithDefaultValueNode field) {
                return Optional.of(new Field(field.fieldName().text().trim(), field.readonlyKeyword().isPresent(),
                        field.typeName(), field.metadata(), field));
            }
            return Optional.empty();
        }
    }
}
