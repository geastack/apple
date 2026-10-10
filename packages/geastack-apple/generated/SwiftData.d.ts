/** @gea-host-no-property-writes */
export declare function openModelContainer(schemaJSON: string): ModelContainer
/** @gea-host-no-property-writes */
export declare function mainModelContext(container: ModelContainer): ModelContext
/** @gea-host-no-property-writes */
export declare function insertModelJSON(context: ModelContext, modelJSON: string): void
/** @gea-host-no-property-writes */
export declare function saveModelContext(context: ModelContext): void
/** @gea-host-no-property-writes */
export declare function fetchModelsJSON(context: ModelContext, descriptorJSON: string): string

export declare class ModelContainer {
}

export declare class ModelContext {
}
