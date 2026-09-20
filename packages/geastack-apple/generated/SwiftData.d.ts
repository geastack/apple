export declare function openModelContainer(schemaJSON: string): ModelContainer
export declare function mainModelContext(container: ModelContainer): ModelContext
export declare function insertModelJSON(context: ModelContext, modelJSON: string): void
export declare function saveModelContext(context: ModelContext): void
export declare function fetchModelsJSON(context: ModelContext, descriptorJSON: string): string

export declare class ModelContainer {
}

export declare class ModelContext {
}
