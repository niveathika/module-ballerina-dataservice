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

import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.RecordTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * Validates the `@dataservice:Expose` annotations and the field rules of a persist model, once per module.
 */
public class PersistModelValidator implements AnalysisTask<SyntaxNodeAnalysisContext> {

    @Override
    public void perform(SyntaxNodeAnalysisContext ctx) {
        if (!(ctx.node() instanceof ModulePartNode module) || !PluginUtils.isPersistModel(ctx)) {
            return;
        }
        Map<String, TypeDefinitionNode> entities = new HashMap<>();
        for (ModuleMemberDeclarationNode member : module.members()) {
            if (member instanceof TypeDefinitionNode type
                    && type.typeDescriptor() instanceof RecordTypeDescriptorNode) {
                entities.put(type.typeName().text().trim(), type);
            }
        }
        for (ModuleMemberDeclarationNode member : module.members()) {
            Set<String> operations = ExposeAnnotationValidator.validate(ctx, member);
            if (member instanceof TypeDefinitionNode type
                    && type.typeDescriptor() instanceof RecordTypeDescriptorNode record) {
                FieldRuleValidator.validate(ctx, type, record, entities, operations);
            }
        }
    }
}
