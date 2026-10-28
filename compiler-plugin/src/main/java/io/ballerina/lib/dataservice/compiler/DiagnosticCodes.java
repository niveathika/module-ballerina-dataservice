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

import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import static io.ballerina.tools.diagnostics.DiagnosticSeverity.ERROR;
import static io.ballerina.tools.diagnostics.DiagnosticSeverity.WARNING;

/**
 * Diagnostics reported by the `ballerina/dataservice` compiler plugin.
 */
public enum DiagnosticCodes {

    DATASERVICE_101("DATASERVICE_101",
            "the @dataservice:Expose annotation is allowed only on a record type in the persist model.", ERROR),
    DATASERVICE_102("DATASERVICE_102",
            "duplicate operation ''{0}'' in the @dataservice:Expose annotation of the entity ''{1}''.", ERROR),
    DATASERVICE_103("DATASERVICE_103", "the field ''{0}'' of the entity ''{1}'' has more than one of " +
            "@dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal.", ERROR),
    DATASERVICE_104("DATASERVICE_104",
            "the key field ''{0}'' of the entity ''{1}'' cannot have @dataservice:{2}.", ERROR),
    DATASERVICE_105("DATASERVICE_105", "the field ''{0}'' of the entity ''{1}'' needs a ''value'' in " +
            "@dataservice:{2}, because it is neither nullable nor generated.", ERROR),
    DATASERVICE_106("DATASERVICE_106",
            "the ''value'' in @dataservice:{0} of the field ''{1}'' of the entity ''{2}'' is not a ''{3}''.", ERROR),
    DATASERVICE_107("DATASERVICE_107", "@dataservice:{0} cannot be used on the relation field ''{1}'' of the " +
            "entity ''{2}'', which has no foreign key.", ERROR),
    DATASERVICE_108("DATASERVICE_108", "@dataservice:{0} cannot be used on the foreign key field ''{1}'' of the " +
            "entity ''{2}''. Use it on the relation field ''{3}''.", ERROR),
    DATASERVICE_109("DATASERVICE_109", "@dataservice:{0} on the field ''{1}'' of the entity ''{2}'' has no " +
            "effect, because the entity does not allow ''{3}''.", WARNING),
    DATASERVICE_110("DATASERVICE_110",
            "invalid scope ''{0}'' in the @dataservice:Expose annotation of the entity ''{1}''.", ERROR),
    DATASERVICE_111("DATASERVICE_111", "the @dataservice:Expose annotation of the entity ''{0}'' sets scopes " +
            "for ''{1}'', which is not in ''operations''.", ERROR);

    private final String code;
    private final String message;
    private final DiagnosticSeverity severity;

    DiagnosticCodes(String code, String message, DiagnosticSeverity severity) {
        this.code = code;
        this.message = message;
        this.severity = severity;
    }

    public String getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }

    public DiagnosticSeverity getSeverity() {
        return severity;
    }
}
