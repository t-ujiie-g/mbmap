export const MAX_BODY_BYTES: number;
export const MAX_DOCUMENT_BYTES: number;
export const MAX_DATA_BYTES: number;
export function readCapped(res: Response, max?: number, tooLarge?: () => Error): Promise<Uint8Array<ArrayBuffer>>;
export function readJsonCapped(res: Response, max?: number, tooLarge?: () => Error): Promise<any>;
export const DATA_TIMEOUT_MS: number;
export function fetchInit(init: unknown, signal?: AbortSignal): RequestInit;
export function dataFetchInit(init: unknown): RequestInit;
