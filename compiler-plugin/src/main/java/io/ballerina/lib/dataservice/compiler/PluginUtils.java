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
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.ProjectKind;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.Location;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;

/**
 * Helpers shared by the validators of the compiler plugin.
 */
final class PluginUtils {

    static final String ORG_NAME = "ballerina";
    static final String MODULE_NAME = "dataservice";
    private static final String PERSIST_DIRECTORY = "persist";
    private static final String BALLERINA_TOML = "Ballerina.toml";

    private PluginUtils() {
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

    static boolean isAnnotation(Optional<? extends Symbol> symbol, String org, String module, String name) {
        if (symbol.isEmpty() || !(symbol.get() instanceof AnnotationSymbol annotationSymbol)) {
            return false;
        }
        Optional<ModuleSymbol> moduleSymbol = annotationSymbol.getModule();
        return moduleSymbol.isPresent() && org.equals(moduleSymbol.get().id().orgName())
                && module.equals(moduleSymbol.get().id().moduleName())
                && annotationSymbol.getName().map(name::equals).orElse(false);
    }

    // The name of a mapping field, without the quotes of a string key or the quote of a quoted identifier.
    static String fieldName(SpecificFieldNode field) {
        Node name = field.fieldName();
        if (name instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.STRING_LITERAL) {
            String text = literal.literalToken().text();
            return text.substring(1, text.length() - 1);
        }
        String text = name.toSourceCode().trim();
        return text.startsWith("'") ? text.substring(1) : text;
    }

    static void report(SyntaxNodeAnalysisContext ctx, DiagnosticCodes code, Location location, Object... args) {
        DiagnosticInfo info = new DiagnosticInfo(code.getCode(), code.getMessage(), code.getSeverity());
        ctx.reportDiagnostic(DiagnosticFactory.createDiagnostic(info, location, args));
    }
}
