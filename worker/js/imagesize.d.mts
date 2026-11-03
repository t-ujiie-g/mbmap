export function imageSize(bytes: Uint8Array): { width: number; height: number } | null;
export function checkImageSize(bytes: Uint8Array, max: number, what?: string): void;
export function checkBlobImageSize(blob: Blob, max: number, what?: string): Promise<void>;
export function decodeImage(blob: Blob): Promise<ImageBitmap>;
