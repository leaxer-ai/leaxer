/**
 * Chat-related TypeScript types for the Leaxer chat system.
 */

import * as pdfjsLib from 'pdfjs-dist';

// Configure pdf.js worker
pdfjsLib.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url
).toString();

/**
 * Supported MIME types for attachments.
 */

export const IMAGE_MIME_TYPES = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
] as const;

export const PDF_MIME_TYPE = 'application/pdf' as const;

export type ImageMimeType = typeof IMAGE_MIME_TYPES[number];
export type AttachmentMimeType = ImageMimeType | 'text/plain' | 'application/pdf' | 'application/octet-stream';

/**
 * An attachment in a chat message.
 */
export interface ChatAttachment {
  id: string;
  name: string;
  mimeType: AttachmentMimeType;
  size: number;
  /** For text files, the extracted content */
  textContent?: string;
  /** For images, the base64 data URL */
  dataUrl?: string;
  /** Whether this requires a multimodal model */
  requiresVision: boolean;
}

/**
 * Web search reference link with optional OG metadata.
 */
export interface SearchReference {
  index: number;
  title: string;
  url: string;
  description?: string;
  image?: string;
  site_name?: string;
  favicon?: string;
}

/**
 * A single version of an artifact document.
 */
export interface ArtifactVersion {
  version: number;
  title: string;
  content: string;
  created_at: number;
}

/**
 * Artifact document generated from chat research with version history.
 */
export interface ChatArtifact {
  id: string;
  title: string;
  content: string;
  created_at: number;
  sources?: SearchReference[];
  status: 'pending' | 'generating' | 'complete' | 'error';
  /** Version history - older versions are stored here */
  versions?: ArtifactVersion[];
  /** Current version number (1-based) */
  currentVersion?: number;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
  isStreaming?: boolean;
  isHiding?: boolean;
  followUps?: string[];
  model?: string;
  references?: SearchReference[];
  attachments?: ChatAttachment[];
  artifact?: ChatArtifact;
}

/**
 * Settings for chat generation.
 */
export interface ChatSettings {
  temperature: number;
  max_tokens: number;
  top_p: number;
  top_k: number;
}

/**
 * A chat session with message history.
 */
export interface ChatSession {
  id: string;
  name: string;
  messages: ChatMessage[];
  created_at: number;
  updated_at: number;
  model: string | null;
  settings: ChatSettings;
  /** If this session was branched from another, stores the original session ID */
  branchedFrom?: string;
}

/**
 * Summary of a chat session for listing.
 */
export interface ChatSessionSummary {
  id: string;
  name: string;
  filename: string;
  modified_at: string;
}

/**
 * LLM model status from the server.
 */
export type ModelStatus = 'idle' | 'loading' | 'ready' | 'error';

/**
 * Model status payload from WebSocket.
 */
export interface ModelStatusPayload {
  status: ModelStatus;
  model: string | null;
  error?: string;
}

/**
 * Stream chunk payload from WebSocket.
 */
export interface StreamChunkPayload {
  content: string;
}

/**
 * Generation complete payload from WebSocket.
 */
export interface GenerationCompletePayload {
  content?: string;
  elapsed_ms?: number;
  aborted?: boolean;
}

/**
 * Generation error payload from WebSocket.
 */
export interface GenerationErrorPayload {
  error: string;
}

/**
 * Message format for the OpenAI-compatible chat completions API.
 */
export interface ChatCompletionMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

/**
 * Default chat settings.
 */
export const DEFAULT_CHAT_SETTINGS: ChatSettings = {
  temperature: 0.7,
  max_tokens: 2048,
  top_p: 0.9,
  top_k: 40,
};

/**
 * Create a new chat session with default values.
 */
export function createChatSession(id?: string, name?: string): ChatSession {
  const timestamp = Date.now();
  const sessionId = id || `chat_${timestamp}_${Math.random().toString(36).slice(2, 7)}`;

  return {
    id: sessionId,
    name: name || 'New Chat',
    messages: [],
    created_at: timestamp,
    updated_at: timestamp,
    model: null,
    settings: { ...DEFAULT_CHAT_SETTINGS },
  };
}

/**
 * Create a new chat message.
 */
export function createChatMessage(
  role: ChatMessage['role'],
  content: string,
  isStreaming = false,
  model?: string,
  attachments?: ChatAttachment[]
): ChatMessage {
  return {
    id: `msg_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    role,
    content,
    timestamp: Date.now(),
    isStreaming,
    model,
    attachments,
  };
}

/**
 * Check if file content is readable as plain text by inspecting bytes.
 * Returns true if file appears to be text (no null bytes, valid UTF-8).
 */
export async function isTextContent(file: File): Promise<boolean> {
  // Check first 8KB for binary indicators
  const slice = file.slice(0, 8192);
  const buffer = await slice.arrayBuffer();
  const bytes = new Uint8Array(buffer);

  // Check for null bytes (strong binary indicator)
  for (const byte of bytes) {
    if (byte === 0) return false;
  }

  // Try to decode as UTF-8
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    return true;
  } catch {
    return false;
  }
}

/**
 * Check if a file is an image.
 */
export function isImageFile(file: File): boolean {
  return IMAGE_MIME_TYPES.includes(file.type as ImageMimeType);
}

/**
 * Check if a file is a PDF.
 */
export function isPdfFile(file: File): boolean {
  return file.type === PDF_MIME_TYPE || file.name.toLowerCase().endsWith('.pdf');
}

/**
 * Extract text from a PDF file using pdf.js (client-side).
 * Throws an error with a user-friendly message if extraction fails.
 */
async function extractPdfText(file: File): Promise<string> {
  try {
    const arrayBuffer = await file.arrayBuffer();
    const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;

    const textParts: string[] = [];

    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const textContent = await page.getTextContent();

      // Build page text preserving structure
      let pageText = '';
      let lastY: number | null = null;

      for (const item of textContent.items) {
        if (!('str' in item)) continue;

        const textItem = item as { str: string; transform?: number[]; hasEOL?: boolean };

        // Check if we need a line break (Y position changed significantly)
        if (textItem.transform && lastY !== null) {
          const currentY = textItem.transform[5];
          if (Math.abs(currentY - lastY) > 5) {
            pageText += '\n';
          }
        }

        pageText += textItem.str;

        // Add space after text unless it ends with whitespace or has EOL
        if (textItem.hasEOL) {
          pageText += '\n';
        } else if (textItem.str && !textItem.str.endsWith(' ') && !textItem.str.endsWith('\n')) {
          pageText += ' ';
        }

        if (textItem.transform) {
          lastY = textItem.transform[5];
        }
      }

      textParts.push(pageText.trim());
    }

    const fullText = textParts.join('\n\n').trim();

    if (!fullText) {
      throw new Error('PDF appears to be empty or contains no extractable text (may be scanned/image-based)');
    }

    return fullText;
  } catch (err) {
    if (err instanceof Error && err.message.includes('no extractable text')) {
      throw err;
    }
    throw new Error(`Failed to extract PDF text: ${err instanceof Error ? err.message : 'Unknown error'}`);
  }
}

/**
 * Error thrown when attachment creation fails with a user-friendly message.
 */
export class AttachmentError extends Error {
  readonly fileName: string;

  constructor(message: string, fileName: string) {
    super(message);
    this.name = 'AttachmentError';
    this.fileName = fileName;
  }
}

/**
 * Create a chat attachment from a file.
 * Returns null if file is binary and not an image or PDF.
 * Throws AttachmentError if there's a specific error (e.g., pdftotext not installed).
 */
export async function createAttachment(file: File): Promise<ChatAttachment | null> {
  const id = `att_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const isImage = isImageFile(file);
  const isPdf = isPdfFile(file);

  // Handle PDF files
  if (isPdf) {
    const textContent = await extractPdfText(file);
    return {
      id,
      name: file.name,
      mimeType: 'application/pdf',
      size: file.size,
      requiresVision: false,
      textContent,
    };
  }

  // For non-images and non-PDFs, check if content is readable as text
  if (!isImage) {
    const isText = await isTextContent(file);
    if (!isText) {
      // Binary file that's not an image or PDF - can't process
      return null;
    }

    // Text file
    return {
      id,
      name: file.name,
      mimeType: 'text/plain',
      size: file.size,
      requiresVision: false,
      textContent: await readFileAsText(file),
    };
  }

  // Image file
  return {
    id,
    name: file.name,
    mimeType: file.type as ImageMimeType,
    size: file.size,
    requiresVision: true,
    dataUrl: await readFileAsDataUrl(file),
  };
}

/**
 * Read a file as text.
 */
function readFileAsText(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(file);
  });
}

/**
 * Read a file as a data URL (base64).
 */
function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

/**
 * Format file size for display.
 */
/**
 * Format file size for display.
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Keywords that indicate a model has vision/multimodal capabilities.
 */
const VISION_MODEL_KEYWORDS = [
  'llava',
  'bakllava',
  'vision',
  'multimodal',
  'mmproj',
  'clip',
  'moondream',
  'obsidian',
  'minicpm-v',
  'qwen-vl',
  'cogvlm',
  'internvl',
  'phi-3-vision',
  'phi-vision',
  'llama-3.2-vision',
  'pixtral',
] as const;

/**
 * Check if a model name/path suggests vision capabilities.
 */
export function isVisionModel(modelPath: string): boolean {
  const lowerPath = modelPath.toLowerCase();
  return VISION_MODEL_KEYWORDS.some(keyword => lowerPath.includes(keyword));
}

/**
 * Model capabilities interface.
 */
export interface ModelCapabilities {
  vision: boolean;
  // Future: audio, documents, etc.
}
