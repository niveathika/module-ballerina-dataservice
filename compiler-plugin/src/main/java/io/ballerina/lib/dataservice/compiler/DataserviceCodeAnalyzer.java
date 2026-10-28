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

import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.CodeAnalysisContext;
import io.ballerina.projects.plugins.CodeAnalyzer;

import java.util.List;

/**
 * Registers the validation of the `@dataservice:Expose` annotation and the field rules.
 */
public class DataserviceCodeAnalyzer extends CodeAnalyzer {

    @Override
    public void init(CodeAnalysisContext context) {
        context.addSyntaxNodeAnalysisTask(new ExposeAnnotationValidator(),
                List.of(SyntaxKind.TYPE_DEFINITION, SyntaxKind.ENUM_DECLARATION, SyntaxKind.CLASS_DEFINITION));
        context.addSyntaxNodeAnalysisTask(new FieldRuleValidator(), SyntaxKind.TYPE_DEFINITION);
    }
}
