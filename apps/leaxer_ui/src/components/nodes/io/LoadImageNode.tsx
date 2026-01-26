import { memo, useRef, useState, useMemo, useCallback } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { apiFetch } from '@/lib/fetch';
import { useSettingsStore } from '@/stores/settingsStore';
import { Button } from '@/components/ui/button';

export const LoadImageNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Get the stored path and URL from node data
  const imagePath = data.path as string | undefined;
  const imageUrl = data._imageUrl as string | undefined;

  // Construct the preview URL
  const previewUrl = useMemo(() => {
    if (!imageUrl) return undefined;
    // If it's already a full URL, use as-is
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    // If it's a relative path, prepend the API base URL
    if (imageUrl.startsWith('/')) {
      return `${getApiBaseUrl()}${imageUrl}`;
    }
    return imageUrl;
  }, [imageUrl, getApiBaseUrl]);

  const handleBrowseClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileChange = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await apiFetch(`${getApiBaseUrl()}/api/upload/image`, {
        method: 'POST',
        body: formData,
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error || 'Upload failed');
      }

      // Update node data with the path (for backend) and URL (for preview)
      updateNodeData(id, {
        path: result.path,
        _imageUrl: result.url,
        _filename: result.filename,
      });
    } catch (err) {
      console.error('Failed to upload image:', err);
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setIsUploading(false);
      // Reset the input so the same file can be re-selected
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  }, [getApiBaseUrl, id, updateNodeData]);

  const filename = data._filename as string | undefined;

  return (
    <BaseNode
      nodeId={id}
      title="Load Image"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      hasError={!!error}
      errorMessage={error || undefined}
      handles={[
        { id: 'image', type: 'source', position: Position.Right, label: 'Image', dataType: 'IMAGE' },
      ]}
    >
      <div className="space-y-3">
        {/* Hidden file input */}
        <input
          ref={fileInputRef}
          type="file"
          accept="image/png,image/jpeg,image/gif,image/webp,image/bmp,image/tiff"
          onChange={handleFileChange}
          className="hidden"
        />

        {/* Image preview */}
        <div className="relative">
          {previewUrl ? (
            <img
              src={previewUrl}
              alt="Loaded image"
              className="rounded border border-overlay-0 bg-crust"
              style={{
                maxWidth: '256px',
                maxHeight: '256px',
                width: 'auto',
                height: 'auto',
              }}
            />
          ) : (
            <div
              className="rounded border-2 border-dashed border-overlay-0 bg-crust/30 flex items-center justify-center text-text-muted text-xs"
              style={{ width: '200px', height: '150px' }}
            >
              No image loaded
            </div>
          )}
        </div>

        {/* Filename display */}
        {filename && (
          <div
            className="text-xs truncate px-1"
            style={{ color: 'var(--color-text-muted)', maxWidth: '256px' }}
            title={imagePath}
          >
            {filename}
          </div>
        )}

        {/* Browse button */}
        <Button
          variant="outline"
          size="sm"
          onClick={handleBrowseClick}
          disabled={isUploading}
          className="nodrag w-full text-xs h-8"
        >
          {isUploading ? 'Uploading...' : 'Browse...'}
        </Button>

        {/* Error message */}
        {error && (
          <div className="text-xs px-1" style={{ color: 'var(--color-error)' }}>
            {error}
          </div>
        )}
      </div>
    </BaseNode>
  );
});

LoadImageNode.displayName = 'LoadImageNode';
