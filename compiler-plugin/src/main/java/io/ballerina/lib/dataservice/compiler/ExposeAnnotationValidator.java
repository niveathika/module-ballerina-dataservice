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

import io.ballerina.compiler.api.symbols.AnnotationAttachmentSymbol;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeDefinitionSymbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_101;
import static io.ballerina.lib.dataservice.compiler.DiagnosticCodes.DATASERVICE_102;

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
            if (!isExposeAnnotation(ctx.semanticModel().symbol(annotation))) {
                continue;
            }
            if (typeDefinition.typeDescriptor().kind() != SyntaxKind.RECORD_TYPE_DESC || !isPersistModel(ctx)) {
                report(ctx, DATASERVICE_101, annotation.location());
                continue;
            }
            validateOperations(ctx, typeDefinition, annotation);
        }
    }

    private static boolean isExposeAnnotation(Optional<? extends Symbol> symbol) {
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

    // The annotation is a const annotation, so its evaluated value also covers operations given as a constant.
    private static void validateOperations(SyntaxNodeAnalysisContext ctx, TypeDefinitionNode typeDefinition,
                                           AnnotationNode annotation) {
        Optional<Symbol> symbol = ctx.semanticModel().symbol(typeDefinition);
        if (symbol.isEmpty() || !(symbol.get() instanceof TypeDefinitionSymbol type)) {
            return;
        }
        for (AnnotationAttachmentSymbol attachment : type.annotAttachments()) {
            if (!isExposeAnnotation(Optional.of(attachment.typeDescriptor())) || !attachment.isConstAnnotation()) {
                continue;
            }
            Set<String> duplicates = duplicates(attachment.attachmentValue().map(ConstantValue::value).orElse(null));
            for (String operation : duplicates) {
                report(ctx, DATASERVICE_102, operationsLocation(annotation), operation);
            }
        }
    }

    private static Set<String> duplicates(Object config) {
        Set<String> duplicates = new LinkedHashSet<>();
        if (!(unwrap(config) instanceof Map<?, ?> fields)
                || !(unwrap(fields.get(OPERATIONS_FIELD)) instanceof List<?> operations)) {
            return duplicates;
        }
        Set<String> seen = new HashSet<>();
        for (Object operation : operations) {
            String value = String.valueOf(unwrap(operation));
            if (!seen.add(value)) {
                duplicates.add(value);
            }
        }
        return duplicates;
    }

    private static Object unwrap(Object value) {
        return value instanceof ConstantValue constant ? unwrap(constant.value()) : value;
    }

    private static Location operationsLocation(AnnotationNode annotation) {
        if (annotation.annotValue().isPresent()) {
            for (MappingFieldNode field : annotation.annotValue().get().fields()) {
                if (field instanceof SpecificFieldNode specificField && specificField.valueExpr().isPresent()
                        && OPERATIONS_FIELD.equals(specificField.fieldName().toSourceCode().trim())) {
                    return specificField.valueExpr().get().location();
                }
            }
        }
        return annotation.location();
    }

    private static void report(SyntaxNodeAnalysisContext ctx, DiagnosticCodes code, Location location,
                               Object... args) {
        DiagnosticInfo info = new DiagnosticInfo(code.getCode(), code.getMessage(), code.getSeverity());
        ctx.reportDiagnostic(DiagnosticFactory.createDiagnostic(info, location, args));
    }
}
